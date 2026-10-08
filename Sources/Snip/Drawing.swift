import AppKit

struct Stroke {
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var highlighter: Bool
}

enum Tool { case pen, highlighter, eraser }

enum StrokeRenderer {
    /// Draws strokes in a top-left-origin, y-down context in image pixel coordinates.
    static func draw(_ strokes: [Stroke], in cg: CGContext) {
        for s in strokes where !s.points.isEmpty {
            cg.saveGState()
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(s.width)
            if s.highlighter {
                cg.setBlendMode(.multiply)
                cg.setStrokeColor(s.color.withAlphaComponent(0.65).cgColor)
            } else {
                cg.setStrokeColor(s.color.cgColor)
            }
            cg.move(to: s.points[0])
            if s.points.count == 1 { cg.addLine(to: s.points[0]) }
            for p in s.points.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()
            cg.restoreGState()
        }
    }

    static func render(_ image: CGImage, strokes: [Stroke]) -> CGImage? {
        let w = image.width, h = image.height
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        draw(strokes, in: ctx)
        return ctx.makeImage()
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    static func hit(_ s: Stroke, at p: CGPoint, radius: CGFloat) -> Bool {
        let r = radius + s.width / 2
        if s.points.count == 1 { return hypot(p.x - s.points[0].x, p.y - s.points[0].y) <= r }
        for i in 1..<s.points.count where distance(from: p, toSegment: s.points[i - 1], s.points[i]) <= r { return true }
        return false
    }
}
