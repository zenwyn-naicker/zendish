// Draws the app icon: a plate seen from above. Run from the repo root:
//   swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = size * 0.098
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: size * 0.18, yRadius: size * 0.18).fill()

    let center = NSPoint(x: size / 2, y: size / 2)
    func circle(_ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
    circle(size * 0.285).fill()
    let rim = circle(size * 0.195)
    rim.lineWidth = size * 0.012
    NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.28).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let folder = URL(fileURLWithPath: "assets/Zendish.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = drawIcon(size: CGFloat(size * scale)).representation(using: .png, properties: [:])!
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
try drawIcon(size: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/icon.png"))
