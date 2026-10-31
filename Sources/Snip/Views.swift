import SwiftUI
import AppKit

struct RootView: View {
    @State private var selected: Shot?

    var body: some View {
        if let shot = selected {
            EditorView(shot: shot) { selected = nil }.id(shot.id)
        } else {
            GalleryView { shot in
                if shot.isVideo { NSWorkspace.shared.open(shot.url) } else { selected = shot }
            }
        }
    }
}

// MARK: - Gallery

struct GalleryView: View {
    var onOpen: (Shot) -> Void
    @ObservedObject private var settings = Settings.shared
    @State private var shots: [Shot] = []
    @State private var recording = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Screenshots").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await CaptureController.shared.start() }
                } label: {
                    Label("New Screenshot", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleRecording()
                } label: {
                    Label(recording ? "Stop Recording" : "Record Screen", systemImage: recording ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(recording ? .red : nil)
                Button { (NSApp.delegate as? AppDelegate)?.openSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings")
            }
            .padding(14)
            Divider()
            if shots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("No screenshots yet").font(.headline)
                    Text("Press \(settings.shortcut(.screenshot).display) to capture, or \(settings.shortcut(.recording).display) to record the screen.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(shots) { shot in
                            Thumb(shot: shot)
                                .onTapGesture { onOpen(shot) }
                                .contextMenu {
                                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
                                    Button("Move to Trash", role: .destructive) { trash(shot) }
                                }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .screenshotsChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .recordingChanged)) { _ in
            recording = RecordingController.shared.isRecording
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() { shots = Store.list() }

    private func trash(_ shot: Shot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        reload()
    }
}

struct Thumb: View {
    let shot: Shot
    @State private var image: CGImage?
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if shot.isVideo {
                Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white)
                    .shadow(radius: 4)
            }
        }
        .frame(height: 150)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering ? Color.accentColor : .clear, lineWidth: 2))
        .onHover { hovering = $0 }
        .task(id: shot.date) {
            let url = shot.url
            image = await Store.thumbnail(url)
        }
    }
}

// MARK: - Editor

struct EditorView: View {
    let shot: Shot
    var onClose: () -> Void

    @State private var image: CGImage?
    @State private var strokes: [Stroke] = []
    @State private var current: Stroke?
    @State private var undoStack: [[Stroke]] = []
    @State private var redoStack: [[Stroke]] = []
    @State private var tool: Tool = .pen
    @State private var penColor: NSColor = .systemRed
    @State private var hlColor: NSColor = .systemYellow
    @State private var penWidth: CGFloat = 6
    @State private var hlWidth: CGFloat = 28
    @State private var dirty = false
    @State private var flash: String?

    private let penPalette: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemBlue, .black, .white]
    private let hlPalette: [NSColor] = [.systemYellow, .systemGreen, .systemPink, .systemCyan, .systemOrange]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                if let image { canvas(image, avail: geo.size) }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .overlay(alignment: .bottom) {
            if let flash {
                Text(flash).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear { image = Store.load(shot.url) }
        .onReceive(NotificationCenter.default.publisher(for: .editorUndo)) { _ in undo() }
        .onReceive(NotificationCenter.default.publisher(for: .editorRedo)) { _ in redo() }
        .onReceive(NotificationCenter.default.publisher(for: .editorSave)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .editorCopy)) { _ in copy() }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { close() } label: { Label("Back", systemImage: "chevron.left") }
            Divider().frame(height: 20)
            toolButton(.pen, "pencil.tip", "Pen")
            toolButton(.highlighter, "highlighter", "Highlighter")
            toolButton(.eraser, "eraser", "Eraser – click or drag over strokes")
            Divider().frame(height: 20)
            if tool != .eraser {
                ForEach(Array((tool == .pen ? penPalette : hlPalette).enumerated()), id: \.offset) { _, c in
                    swatch(c)
                }
                Slider(value: tool == .pen ? $penWidth : $hlWidth, in: tool == .pen ? 2...24 : 12...60)
                    .frame(width: 100)
            }
            Spacer()
            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(undoStack.isEmpty).help("Undo (⌘Z)")
            Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(redoStack.isEmpty).help("Redo (⇧⌘Z)")
            Divider().frame(height: 20)
            Button { copy() } label: { Image(systemName: "doc.on.doc") }.help("Copy image")
            Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(!dirty).help("Save (⌘S)")
            Button(role: .destructive) { deleteShot() } label: { Image(systemName: "trash") }.help("Delete screenshot")
        }
        .padding(10)
    }

    private func toolButton(_ t: Tool, _ symbol: String, _ help: String) -> some View {
        Button { tool = t } label: {
            Image(systemName: symbol).frame(width: 26, height: 22)
        }
        .buttonStyle(.bordered)
        .tint(tool == t ? .accentColor : nil)
        .help(help)
    }

    private func swatch(_ c: NSColor) -> some View {
        let selected = (tool == .pen ? penColor : hlColor) == c
        return Circle().fill(Color(nsColor: c)).frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 2.5 : 0).padding(-3))
            .onTapGesture { if tool == .pen { penColor = c } else { hlColor = c } }
    }

    // MARK: canvas

    private func canvas(_ image: CGImage, avail: CGSize) -> some View {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = min((avail.width - 40) / iw, (avail.height - 40) / ih, 1)
        let size = CGSize(width: iw * scale, height: ih * scale)
        return Canvas { ctx, sz in
            ctx.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: sz))
            ctx.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                StrokeRenderer.draw(strokes + (current.map { [$0] } ?? []), in: cg)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.25), radius: 6)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in drag(to: CGPoint(x: v.location.x / scale, y: v.location.y / scale), scale: scale) }
            .onEnded { _ in endDrag() })
        .frame(width: avail.width, height: avail.height)
    }

    @State private var dragSnapshot: [Stroke]?

    private func drag(to p: CGPoint, scale: CGFloat) {
        if dragSnapshot == nil { dragSnapshot = strokes }
        switch tool {
        case .eraser:
            let r = 10 / scale
            strokes.removeAll { StrokeRenderer.hit($0, at: p, radius: r) }
        case .pen, .highlighter:
            if current == nil {
                let hl = tool == .highlighter
                current = Stroke(points: [p], color: hl ? hlColor : penColor, width: hl ? hlWidth : penWidth, highlighter: hl)
            } else {
                current?.points.append(p)
            }
        }
    }

    private func endDrag() {
        defer { dragSnapshot = nil }
        guard let before = dragSnapshot else { return }
        if let c = current {
            strokes.append(c)
            current = nil
        }
        if strokes.count != before.count || tool != .eraser {
            undoStack.append(before)
            redoStack.removeAll()
            dirty = true
        }
    }

    // MARK: actions

    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = prev
        dirty = true
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
        dirty = true
    }

    private func flattened() -> CGImage? {
        guard let image else { return nil }
        return strokes.isEmpty ? image : StrokeRenderer.render(image, strokes: strokes)
    }

    private func save() {
        guard dirty, let out = flattened() else { return }
        if Store.write(out, to: shot.url) {
            dirty = false
            NotificationCenter.default.post(name: .screenshotsChanged, object: nil)
            toast("Saved")
        }
    }

    private func copy() {
        guard let out = flattened() else { return }
        Store.copyToClipboard(out)
        toast("Copied to clipboard")
    }

    private func close() {
        save()
        onClose()
    }

    private func deleteShot() {
        dirty = false
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        NotificationCenter.default.post(name: .screenshotsChanged, object: nil)
        onClose()
    }

    private func toast(_ text: String) {
        withAnimation { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { flash = nil } }
    }
}
