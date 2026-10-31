import AppKit

/// A precise vector crosshair: thin white lines with a dark outline (readable on any background)
/// and an open center so you can see the exact pixel you're selecting.
enum Crosshair {
    static let cursor: NSCursor = {
        let pts: CGFloat = 33  // odd size so the hotspot sits on a pixel
        let image = NSImage(size: NSSize(width: pts, height: pts))
        for scale in [1, 2] as [CGFloat] {
            let px = Int(pts * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: pts, height: pts)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(in: pts)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: pts / 2, y: pts / 2))
    }()

    private static func draw(in size: CGFloat) {
        let c = size / 2, gap: CGFloat = 4, arm: CGFloat = 15
        func arms(_ width: CGFloat, _ color: NSColor) {
            let p = NSBezierPath()
            p.lineWidth = width
            p.lineCapStyle = .butt
            p.move(to: NSPoint(x: c - arm, y: c)); p.line(to: NSPoint(x: c - gap, y: c))
            p.move(to: NSPoint(x: c + gap, y: c)); p.line(to: NSPoint(x: c + arm, y: c))
            p.move(to: NSPoint(x: c, y: c - arm)); p.line(to: NSPoint(x: c, y: c - gap))
            p.move(to: NSPoint(x: c, y: c + gap)); p.line(to: NSPoint(x: c, y: c + arm))
            color.setStroke()
            p.stroke()
        }
        arms(3, NSColor.black.withAlphaComponent(0.75))  // outline
        arms(1, .white)
        // center dot marks the exact hotspot
        let dot = NSBezierPath(ovalIn: NSRect(x: c - 1.5, y: c - 1.5, width: 3, height: 3))
        NSColor.black.withAlphaComponent(0.75).setFill(); dot.fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: c - 0.5, y: c - 0.5, width: 1, height: 1)).fill()
    }
}
