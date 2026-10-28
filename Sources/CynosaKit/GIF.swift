// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ImageIO

public enum GIFError: Error, LocalizedError {
    case unreadable, empty
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Dosya okunamadı"
        case .empty: return "Dosyada kare yok"
        }
    }
}

public enum ScaleMode: String, Codable, CaseIterable, Sendable { case fill, fit, stretch }

/// Animated image (GIF, APNG, WebP, HEICS) pre-rendered to keyboard frames.
public final class GIFAnimation: Animation {
    public let frames: [Frame]
    public let delays: [TimeInterval]
    public let duration: TimeInterval
    public var speed: Double = 1
    private let starts: [TimeInterval]

    public convenience init(url: URL, mode: ScaleMode = .fill, vivid: Bool = true) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw GIFError.unreadable }
        try self.init(source: source, mode: mode, vivid: vivid)
    }

    public init(source: CGImageSource, mode: ScaleMode = .fill, vivid: Bool = true) throws {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw GIFError.empty }
        var frames: [Frame] = []
        var delays: [TimeInterval] = []
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(Self.downsample(image, mode: mode, vivid: vivid))
            delays.append(Self.delay(source, i))
        }
        guard !frames.isEmpty else { throw GIFError.empty }
        self.frames = frames
        self.delays = delays
        var t = 0.0
        starts = delays.map { d in defer { t += d }; return t }
        duration = t
    }

    /// Unchanged frames are skipped by `Keyboard.show`, so sampling at 60 fps only costs
    /// traffic when the GIF actually changes and keeps its timing exact.
    public var preferredFPS: Double? { frames.count > 1 ? 60 : 1 }

    public func frame(at time: TimeInterval) -> Frame {
        guard frames.count > 1 else { return frames[0] }
        let t = (time * speed).truncatingRemainder(dividingBy: duration)
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return frames[lo]
    }

    static func delay(_ source: CGImageSource, _ index: Int) -> TimeInterval {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in containers {
            guard let d = props[dict] as? [CFString: Any] else { continue }
            let v = (d[unclamped] as? Double) ?? (d[clamped] as? Double) ?? 0
            // Browsers treat ≤10 ms as 100 ms; do the same.
            return v <= 0.011 ? 0.1 : v
        }
        return 0.1
    }

    /// Renders at 4× key resolution, then box-filters to one sample per key.
    static func downsample(_ image: CGImage, mode: ScaleMode, vivid: Bool) -> Frame {
        let k = 4
        let w = Frame.columns * k, h = Frame.rows * k
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            let iw = Double(image.width), ih = Double(image.height)
            let target = CGRect(x: 0, y: 0, width: w, height: h)
            let rect: CGRect
            switch mode {
            case .stretch:
                rect = target
            case .fill, .fit:
                let s = mode == .fill ? max(Double(w) / iw, Double(h) / ih) : min(Double(w) / iw, Double(h) / ih)
                let dw = iw * s, dh = ih * s
                rect = CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh)
            }
            ctx.draw(image, in: rect)
        }
        return Frame { r, c in
            var sr = 0, sg = 0, sb = 0
            for y in 0..<k {
                for x in 0..<k {
                    let i = ((r * k + y) * w + c * k + x) * 4
                    sr += Int(buffer[i]); sg += Int(buffer[i + 1]); sb += Int(buffer[i + 2])
                }
            }
            let n = Double(k * k)
            let px = RGB(UInt8(Double(sr) / n), UInt8(Double(sg) / n), UInt8(Double(sb) / n))
            return vivid ? Self.vivid(px) : px
        }
    }

    /// LEDs are linear emitters; pull midtones down and push saturation so the image reads like on screen.
    static func vivid(_ c: RGB) -> RGB {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        func f(_ v: Double) -> UInt8 {
            let sat = min(max(l + (v - l) * 1.25, 0), 1)
            return UInt8((pow(sat, 1.6) * 255).rounded())
        }
        return RGB(f(r), f(g), f(b))
    }
}
