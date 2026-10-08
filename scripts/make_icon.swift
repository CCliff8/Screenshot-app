// Generates Resources/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    let t = NSAffineTransform(); t.scale(by: k); t.concat()

    // Body (macOS icon grid: 824pt square centered in 1024)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.82, blue: 0.70, alpha: 1),   // mint
                        NSColor(srgbRed: 0.18, green: 0.62, blue: 0.96, alpha: 1)])!  // sky
        .draw(in: shape, angle: 40)
    // soft top gloss
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Highlighter swipe (lime, behind the brackets)
    let swipe = NSBezierPath(roundedRect: NSRect(x: 290, y: 440, width: 444, height: 120), xRadius: 40, yRadius: 40)
    NSColor(srgbRed: 0.85, green: 1.0, blue: 0.35, alpha: 0.95).setFill()
    swipe.fill()

    // Selection corner brackets
    let white = NSColor.white
    white.setStroke()
    let L: CGFloat = 150, lo: CGFloat = 240, hi: CGFloat = 784
    for (cx, cy, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx + dx * L, y: cy))
        p.line(to: NSPoint(x: cx, y: cy))
        p.line(to: NSPoint(x: cx, y: cy + dy * L))
        p.lineWidth = 52; p.lineCapStyle = .round; p.lineJoinStyle = .round
        p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "Resources/AppIcon.iconset"  // temp; convert with iconutil, then delete
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                              ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                              ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes { try render(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png")) }
