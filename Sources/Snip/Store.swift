import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

extension Notification.Name {
    static let screenshotsChanged = Notification.Name("snip.screenshotsChanged")
    static let editorUndo = Notification.Name("snip.editorUndo")
    static let editorRedo = Notification.Name("snip.editorRedo")
    static let editorSave = Notification.Name("snip.editorSave")
    static let editorCopy = Notification.Name("snip.editorCopy")
    static let screenshotCaptured = Notification.Name("snip.screenshotCaptured")
    static let recordingChanged = Notification.Name("snip.recordingChanged")
}

struct Shot: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
    var isVideo: Bool { url.pathExtension.lowercased() == "mp4" }
}

enum Store {
    static let folder: URL = {
        let url = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func list() -> [Shot] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { ["png", "mp4"].contains($0.pathExtension.lowercased()) }
            .map { Shot(url: $0, date: (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            .sorted { $0.date > $1.date }
    }

    static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Saves a new screenshot with a macOS-style name and returns its URL.
    static func save(_ image: CGImage) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(f.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        guard write(image, to: url) else { return nil }
        NotificationCenter.default.post(name: .screenshotsChanged, object: nil)
        NotificationCenter.default.post(name: .screenshotCaptured, object: url)
        return url
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func thumbnail(_ url: URL, maxPixel: Int = 640) async -> CGImage? {
        if url.pathExtension.lowercased() == "mp4" {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            if let r = try? await gen.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)) { return r.image }
            return try? await gen.image(at: .zero).image
        }
        return await Task.detached { () -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
    }

    static func newVideoURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return folder.appendingPathComponent("Recording \(f.string(from: Date())).mp4")
    }

    static func copyToClipboard(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    /// Copies a file from the gallery: the image for screenshots, the file itself for videos.
    static func copyFile(_ url: URL) {
        if url.pathExtension.lowercased() == "mp4" {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
        } else if let image = load(url) {
            copyToClipboard(image)
        }
    }
}
