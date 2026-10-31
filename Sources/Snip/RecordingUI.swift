import AppKit
import SwiftUI

/// The floating control bar and the region outline shown while recording.
/// Both belong to Snip, so ScreenCaptureKit leaves them out of the video.
enum RecordingChrome {
    @MainActor
    static func show(rect: CGRect, screen: NSScreen) -> (NSPanel, NSWindow?) {
        let size = NSSize(width: 276, height: 80)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingBar())
        let v = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.minY + 12))
        panel.orderFrontRegardless()

        var border: NSWindow?
        let full = rect.width >= screen.frame.width - 1 && rect.height >= screen.frame.height - 1
        if !full {
            let f = NSRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height).insetBy(dx: -4, dy: -4)
            let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = .statusBar
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = BorderView(frame: NSRect(origin: .zero, size: f.size))
            w.orderFrontRegardless()
            border = w
        }
        return (panel, border)
    }
}

private final class BorderView: NSView {
    private var observer: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        observer = NotificationCenter.default.addObserver(forName: .recordingChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func draw(_ dirtyRect: NSRect) {
        let state = MainActor.assumeIsolated { RecordingController.shared.state }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2.5, dy: 2.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        switch state {
        case .recording: NSColor.systemRed.setStroke()
        case .paused: NSColor.systemOrange.setStroke()
        default:
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.setLineDash([6, 4], count: 2, phase: 0)
        }
        path.stroke()
    }
}

struct RecordingBar: View {
    @ObservedObject private var rec = RecordingController.shared

    var body: some View {
        HStack(spacing: 10) {
            switch rec.state {
            case .countdown(let n):
                Text("Recording starts in").foregroundStyle(.secondary)
                Text("\(n)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                BarButton(symbol: "xmark", fill: Color.primary.opacity(0.12), label: "Cancel") { rec.cancelCountdown() }
            case .recording, .paused:
                let paused = rec.state == .paused
                TimelineView(.animation(minimumInterval: 0.1)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Circle().fill(paused ? Color.orange : Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(paused ? 1 : 0.65 + 0.35 * sin(t * 4))
                }
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(format(rec.elapsed)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                if paused { Text("Paused").font(.callout).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                BarButton(symbol: paused ? "play.fill" : "pause.fill", fill: Color.primary.opacity(0.12),
                          label: paused ? "Resume recording" : "Pause recording") { rec.togglePause() }
                BarButton(symbol: "stop.fill", fill: .red, foreground: .white, label: "Stop and save") {
                    Task { await rec.stop() }
                }
            case .saved(let url):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                Text("Saved")
                Spacer(minLength: 0)
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.bordered).controlSize(.small)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        .frame(width: 276, height: 80)
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct BarButton: View {
    let symbol: String
    let fill: Color
    var foreground: Color = .primary
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 30, height: 30)
                .background(Circle().fill(fill))
                .overlay(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
