import AppKit
import ScreenCaptureKit

/// Records a region of a display to an .mp4 using ScreenCaptureKit's built-in recording output.
@MainActor
final class RecordingController: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput {
    static let shared = RecordingController()
    private var stream: SCStream?
    private(set) var isRecording = false {
        didSet { NotificationCenter.default.post(name: .recordingChanged, object: nil) }
    }
    private(set) var startedAt = Date()

    /// `rect` is in display points, origin top-left.
    func start(filter: SCContentFilter, rect: CGRect, scale: CGFloat) async {
        guard !isRecording else { return }
        func even(_ v: CGFloat) -> Int { max(2, Int(v.rounded()) / 2 * 2) }

        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = even(rect.width * scale)
        config.height = even(rect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = Store.newVideoURL()
        recConfig.outputFileType = .mp4
        recConfig.videoCodecType = .h264

        do {
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            try s.addRecordingOutput(SCRecordingOutput(configuration: recConfig, delegate: self))
            try await s.startCapture()
            stream = s
            startedAt = Date()
            isRecording = true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't start recording"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
        isRecording = false
    }

    // MARK: delegates (called off the main actor)

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.stream = nil
            self.isRecording = false
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .screenshotsChanged, object: nil)
            NSSound(named: "Pop")?.play()
        }
    }
}
