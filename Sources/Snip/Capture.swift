import AppKit
import ScreenCaptureKit

enum CaptureMode { case screenshot, recording }

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OverlayView: NSView {
    let image: CGImage
    let mode: CaptureMode
    var onFinish: (NSRect?) -> Void
    private var anchor: NSPoint?
    private var selection: NSRect?

    init(frame: NSRect, image: CGImage, mode: CaptureMode, onFinish: @escaping (NSRect?) -> Void) {
        self.image = image
        self.mode = mode
        self.onFinish = onFinish
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Crosshair.cursor) }
    override func viewDidMoveToWindow() { window?.invalidateCursorRects(for: self) }
    override func mouseMoved(with event: NSEvent) { Crosshair.cursor.set() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        if let r = selection {
            ctx.addRect(bounds)
            ctx.addRect(r)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r.insetBy(dx: -0.5, dy: -0.5))
            drawLabel(for: r)
        } else {
            ctx.fill(bounds)
            if anchor == nil {
                drawPill(mode == .recording
                         ? "Drag to select the area to record  ·  Return for full screen  ·  Esc to cancel"
                         : "Drag to select an area  ·  Return for full screen  ·  Esc to cancel",
                         at: NSPoint(x: bounds.midX, y: bounds.maxY - 70))
            }
        }
    }

    private func drawPill(_ string: String, at center: NSPoint) {
        let text = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let pill = NSRect(origin: origin, size: size).insetBy(dx: -14, dy: -8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    private func drawLabel(for r: NSRect) {
        let text = "\(Int(r.width)) × \(Int(r.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        var origin = NSPoint(x: r.minX, y: r.maxY + 6)
        if origin.y + size.height + 6 > bounds.maxY { origin.y = r.minY - size.height - 10 }
        let pill = NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let a = anchor else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(a.x - p.x), height: abs(a.y - p.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        anchor = nil
        guard let r = selection, r.width >= 3, r.height >= 3 else {
            selection = nil
            needsDisplay = true
            return
        }
        onFinish(r)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) }  // esc
        else if event.keyCode == 36 || event.keyCode == 76 { onFinish(bounds) }  // return: full screen
    }
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private var overlay: OverlayWindow?
    private var busy = false

    private var image: CGImage?
    private var filter: SCContentFilter?
    private var scale: CGFloat = 2
    private var mode: CaptureMode = .screenshot
    private var screen: NSScreen?
    private var hiddenWindow: NSWindow?

    func start(mode: CaptureMode = .screenshot, fullScreen: Bool = false) async {
        let st = RecordingController.shared.state
        if case .countdown = st { return }
        guard !busy, overlay == nil, !RecordingController.shared.isRecording else { return }
        busy = true
        defer { busy = false }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number }) else { return }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            self.image = image
            self.filter = filter
            self.scale = scale
            self.mode = mode
            self.screen = screen
            if fullScreen {
                hideMainWindow()
                finish(NSRect(origin: .zero, size: screen.frame.size), viewSize: screen.frame.size)
            } else {
                present(image, on: screen, mode: mode)
            }
        } catch {
            showPermissionAlert()
        }
    }

    private func present(_ image: CGImage, on screen: NSScreen, mode: CaptureMode) {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, mode: mode) { [weak self] rect in
            self?.finish(rect, viewSize: screen.frame.size)
        }
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        overlay = window
        hideMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        window.acceptsMouseMovedEvents = true
        Crosshair.cursor.set()
    }

    /// Keeps the gallery out of the way during a capture; it comes back after a screenshot or cancel.
    private func hideMainWindow() {
        hiddenWindow = NSApp.windows.first { $0.title == "Snip" && $0.isVisible }
        hiddenWindow?.orderOut(nil)
    }

    /// `rect` is in view points, origin bottom-left.
    private func finish(_ rect: NSRect?, viewSize: CGSize) {
        overlay?.orderOut(nil)
        overlay = nil
        defer { image = nil; filter = nil; screen = nil }
        let restore = hiddenWindow
        hiddenWindow = nil
        guard let rect, let image, let filter, let screen else { restore?.makeKeyAndOrderFront(nil); return }

        switch mode {
        case .screenshot:
            let sx = CGFloat(image.width) / viewSize.width
            let sy = CGFloat(image.height) / viewSize.height
            let px = CGRect(x: rect.minX * sx, y: (viewSize.height - rect.maxY) * sy,
                            width: rect.width * sx, height: rect.height * sy).integral
            guard let cropped = image.cropping(to: px) else { return }
            Store.copyToClipboard(cropped)
            _ = Store.save(cropped)
            NSSound(named: "Pop")?.play()
            restore?.makeKeyAndOrderFront(nil)
        case .recording:  // the app stays out of the way; the floating control bar takes over
            let topLeft = CGRect(x: rect.minX, y: viewSize.height - rect.maxY, width: rect.width, height: rect.height)
            let scale = self.scale
            RecordingController.shared.windowToRestore = restore
            Task { await RecordingController.shared.start(filter: filter, rect: topLeft, scale: scale, screen: screen) }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen recording permission needed"
        alert.informativeText = "Allow Snip under System Settings → Privacy & Security → Screen & System Audio Recording, then restart Snip."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
