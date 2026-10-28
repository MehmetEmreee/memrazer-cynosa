// SPDX-License-Identifier: GPL-2.0-or-later
// Renders the app icon: usage `swift make-icon.swift <out.iconset>`
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.03, alpha: 1)])!.draw(in: bg, angle: -90)

    let cols = 8, rows = 4
    let key = 70 * s, gap = 16 * s
    let w = CGFloat(cols) * key + CGFloat(cols - 1) * gap
    let h = CGFloat(rows) * key + CGFloat(rows - 1) * gap
    let ox = (CGFloat(px) - w) / 2, oy = (CGFloat(px) - h) / 2
    for r in 0..<rows {
        for c in 0..<cols {
            let hue = (CGFloat(c) / CGFloat(cols) * 0.75 + CGFloat(r) * 0.04).truncatingRemainder(dividingBy: 1)
            let color = NSColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 1)
            let rect = NSRect(x: ox + CGFloat(c) * (key + gap), y: oy + CGFloat(r) * (key + gap), width: key, height: key)
            let shadow = NSShadow()
            shadow.shadowColor = color.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 28 * s
            shadow.set()
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16 * s, yRadius: 16 * s).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
