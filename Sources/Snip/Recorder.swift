import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecordingState: Equatable {
    case idle
    case countdown(Int)
    case recording
    case paused
    case saved(URL)
}

/// Receives frames from ScreenCaptureKit and writes them to an .mp4. Supports pausing by dropping
/// frames and shifting later timestamps back, so the paused time doesn't appear in the video.
final class FrameWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "snip.frames")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var paused = false
    private var resumePending = false
    private var offset = CMTime.zero
    private var lastPTS = CMTime.zero

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let pixels = width * height
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2_000_000, min(40_000_000, pixels * 4))],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func setPaused(_ p: Bool) {
        queue.async {
            if p { self.paused = true } else if self.paused { self.paused = false; self.resumePending = true }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, CMSampleBufferGetImageBuffer(sb) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              !paused
        else { return }

        let pts = sb.presentationTimeStamp
        if resumePending { offset = offset + (pts - lastPTS); resumePending = false }
        lastPTS = pts
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)
            started = true
        }
        var timing = CMSampleTimingInfo(duration: sb.duration, presentationTimeStamp: pts - offset, decodeTimeStamp: .invalid)
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing, sampleBufferOut: &adjusted)
        if let adjusted, input.isReadyForMoreMediaData { input.append(adjusted) }
    }

    /// Returns false if no frame was ever written.
    func finish() async -> Bool {
        await withCheckedContinuation { cont in
            queue.async {
                guard self.started else { self.writer.cancelWriting(); cont.resume(returning: false); return }
                self.input.markAsFinished()
                self.writer.finishWriting { cont.resume(returning: self.writer.status == .completed) }
            }
        }
    }
}

/// Owns the recording lifecycle: countdown → recording ⇄ paused → saved.
@MainActor
final class RecordingController: NSObject, ObservableObject, SCStreamDelegate {
    static let shared = RecordingController()

    @Published private(set) var state: RecordingState = .idle {
        didSet { NotificationCenter.default.post(name: .recordingChanged, object: nil) }
    }
    var isRecording: Bool { state == .recording || state == .paused }

    private var stream: SCStream?
    private var writer: FrameWriter?
    private var url: URL?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var bar: NSPanel?
    private var border: NSWindow?
    /// The gallery window that was open when recording began; brought back once recording ends.
    var windowToRestore: NSWindow?

    private func restoreWindow() {
        guard let w = windowToRestore else { return }
        windowToRestore = nil
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Recorded time, excluding pauses.
    var elapsed: TimeInterval { accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0) }

    /// `rect` is in display points, origin top-left.
    func start(filter: SCContentFilter, rect: CGRect, scale: CGFloat, screen: NSScreen) async {
        if case .saved = state { teardown(); state = .idle }
        guard state == .idle else { return }
        func even(_ v: CGFloat) -> Int { max(2, Int(v.rounded()) / 2 * 2) }

        (bar, border) = RecordingChrome.show(rect: rect, screen: screen)
        for n in [3, 2, 1] {
            state = .countdown(n)
            try? await Task.sleep(for: .seconds(1))
            guard case .countdown = state else { return }  // cancelled
        }

        do {
            let width = even(rect.width * scale), height = even(rect.height * scale)
            let url = Store.newVideoURL()
            let writer = try FrameWriter(url: url, width: width, height: height)
            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            try await s.startCapture()
            stream = s
            self.writer = writer
            self.url = url
            accumulated = 0
            segmentStart = Date()
            state = .recording
        } catch {
            teardown()
            state = .idle
            restoreWindow()
            let alert = NSAlert()
            alert.messageText = "Couldn't start recording"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func cancelCountdown() {
        guard case .countdown = state else { return }
        teardown()
        state = .idle
        restoreWindow()
    }

    func pause() {
        guard state == .recording else { return }
        writer?.setPaused(true)
        accumulated = elapsed
        segmentStart = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        writer?.setPaused(false)
        segmentStart = Date()
        state = .recording
    }

    func togglePause() { state == .paused ? resume() : pause() }

    func stop() async {
        guard isRecording, let s = stream else { return }
        stream = nil
        accumulated = elapsed
        segmentStart = nil
        border?.orderOut(nil)
        try? await s.stopCapture()
        let ok = await writer?.finish() ?? false
        let url = self.url
        writer = nil
        self.url = nil
        NotificationCenter.default.post(name: .screenshotsChanged, object: nil)
        guard ok, let url else { teardown(); state = .idle; restoreWindow(); return }
        Sound.recordingSaved()
        state = .saved(url)
        restoreWindow()
        try? await Task.sleep(for: .seconds(5))
        if state == .saved(url) { teardown(); state = .idle }
    }

    private func teardown() {
        bar?.orderOut(nil)
        border?.orderOut(nil)
        bar = nil
        border = nil
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in await self.stop() }
    }
}
