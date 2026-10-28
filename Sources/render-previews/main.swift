// SPDX-License-Identifier: GPL-2.0-or-later
// Renders the README preview GIFs from the real effect engine: `swift run render-previews [outdir]`
import CoreGraphics
import CynosaKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic RNG so the previews are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let fps = 15.0
let key = 28.0, gap = 6.0, pad = 22.0
let width = Int(Double(Frame.columns) * key + Double(Frame.columns - 1) * gap + pad * 2)
let height = Int(Double(Frame.rows) * key + Double(Frame.rows - 1) * gap + pad * 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// Same look as the app's keyboard preview: dark deck, rounded keys, coloured glow.
func draw(_ frame: Frame) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    for r in 0..<Frame.rows {
        for c in 0..<Frame.columns {
            let px = frame[r, c]
            let color = CGColor(srgbRed: Double(px.r) / 255, green: Double(px.g) / 255, blue: Double(px.b) / 255, alpha: 1)
            let y = Double(height) - pad - Double(r + 1) * key - Double(r) * gap // CG origin is bottom-left
            let rect = CGRect(x: pad + Double(c) * (key + gap), y: y, width: key, height: key)
            let path = CGPath(roundedRect: rect, cornerWidth: key * 0.22, cornerHeight: key * 0.22, transform: nil)

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: px == .black ? 0 : key * 0.7, color: color)
            ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1))
            ctx.addPath(path); ctx.fillPath()
            ctx.restoreGState()

            ctx.setFillColor(color.copy(alpha: 0.92)!)
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.06))
            ctx.addPath(path); ctx.strokePath()
        }
    }
    return ctx.makeImage()!
}

func writeGIF(_ frames: [Frame], to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
    for f in frames { CGImageDestinationAddImage(dest, draw(f), delay) }
    precondition(CGImageDestinationFinalize(dest), "could not write \(url.path)")
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(url.lastPathComponent)  \(frames.count) frames  \(size / 1024) KB")
}

func record(_ animation: Animation, from start: Double = 0, seconds: Double, timeScale: Double = 1) -> [Frame] {
    (0..<Int(seconds * fps)).map { animation.frame(at: start + Double($0) / fps * timeScale) }
}

func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/previews", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Fast day: a whole day in 18 s while clouds and planes keep their real speed.
// Picks the seed whose airliner is visible (not hidden behind clouds) for the most frames.
let dawn = utc("2026-06-21T01:30:00Z")
let length = 18.0
let airframe: Set<RGB> = [RGB(225, 230, 240), RGB(130, 135, 150)] // SkyAnimation day plane colours
func fastDay(seed: UInt64) -> SkyAnimation {
    let sky = SkyAnimation(cloudiness: 0.3, timeLapse: true, clock: { dawn }, rng: SplitMix64(state: seed))
    sky.timeLapseRate = 86400 / length
    return sky
}
func visiblePlaneFrames(seed: UInt64) -> Int {
    let sky = fastDay(seed: seed)
    return record(sky, seconds: length).filter { f in f.pixels.filter(airframe.contains).count >= 4 }.count
}
let seed = (1...48).map(UInt64.init).max { visiblePlaneFrames(seed: $0) < visiblePlaneFrames(seed: $1) }!
writeGIF(record(fastDay(seed: seed), seconds: length), to: out.appendingPathComponent("sky.gif"))

writeGIF(record(FireAnimation(palette: .classic, intensity: 0.75), seconds: 4),
         to: out.appendingPathComponent("fire.gif"))
