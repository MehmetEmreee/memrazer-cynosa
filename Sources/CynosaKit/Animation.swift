// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public protocol Animation: AnyObject {
    /// Called on the player thread with seconds since start.
    func frame(at time: TimeInterval) -> Frame
    /// Frame rate the animation wants right now; nil uses the player's default.
    /// Read after every frame, so it can rise while something fast is on screen.
    var preferredFPS: Double? { get }
}

extension Animation {
    public var preferredFPS: Double? { nil }
}

// MARK: - Fire

public enum FirePalette: String, Codable, CaseIterable, Sendable {
    case classic, blue, green, purple

    func color(_ heat: Double) -> RGB {
        let h = min(max(heat, 0), 1)
        func ramp(_ stops: [(Double, RGB)]) -> RGB {
            for i in 1..<stops.count where h <= stops[i].0 {
                let (t0, a) = stops[i - 1], (t1, b) = stops[i]
                let k = (h - t0) / (t1 - t0)
                func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) + (Double(y) - Double(x)) * k).rounded()) }
                return RGB(mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b))
            }
            return stops.last!.1
        }
        switch self {
        case .classic: return ramp([(0, .black), (0.25, RGB(90, 0, 0)), (0.5, RGB(220, 30, 0)), (0.75, RGB(255, 110, 0)), (1, RGB(255, 210, 60))])
        case .blue:    return ramp([(0, .black), (0.3, RGB(0, 0, 90)), (0.6, RGB(0, 60, 255)), (0.85, RGB(0, 180, 255)), (1, RGB(180, 240, 255))])
        case .green:   return ramp([(0, .black), (0.3, RGB(0, 60, 0)), (0.6, RGB(20, 200, 0)), (0.85, RGB(120, 255, 30)), (1, RGB(220, 255, 140))])
        case .purple:  return ramp([(0, .black), (0.3, RGB(50, 0, 80)), (0.6, RGB(170, 0, 255)), (0.85, RGB(255, 60, 220)), (1, RGB(255, 190, 255))])
        }
    }
}

/// Cellular fire rising from the space-bar row, simulated at 2×5 the key resolution.
public final class FireAnimation: Animation {
    public var palette: FirePalette
    public var intensity: Double // 0…1

    private let w = Frame.columns * 2
    private let h = Frame.rows * 5
    private var heat: [Double]
    private var lastStep: TimeInterval = 0
    private var rng = SystemRandomNumberGenerator()
    private let stepInterval = 1.0 / 40

    public init(palette: FirePalette = .classic, intensity: Double = 0.7) {
        self.palette = palette
        self.intensity = intensity
        heat = Array(repeating: 0, count: w * h)
    }

    private func step() {
        for x in 0..<w {
            heat[(h - 1) * w + x] = Double.random(in: 0.75...1, using: &rng)
        }
        let decay = 0.06 + (1 - intensity) * 0.12
        for y in 0..<(h - 1) {
            for x in 0..<w {
                let src = (y + 1) * w + x
                let drift = Int.random(in: -1...1, using: &rng)
                let dx = min(max(x + drift, 0), w - 1)
                let cool = Double.random(in: 0...decay, using: &rng)
                heat[y * w + dx] = max(0, heat[src] - cool)
            }
        }
    }

    public func frame(at time: TimeInterval) -> Frame {
        while lastStep + stepInterval <= time {
            step()
            lastStep += stepInterval
        }
        let sx = w / Frame.columns, sy = h / Frame.rows
        return Frame { r, c in
            var sum = 0.0
            for y in 0..<sy { for x in 0..<sx { sum += heat[(r * sy + y) * w + c * sx + x] } }
            return palette.color(sum / Double(sx * sy))
        }
    }
}

// MARK: - Rainbow

public final class RainbowAnimation: Animation {
    public var speed: Double // hue degrees per second
    public init(speed: Double = 90) { self.speed = speed }

    public func frame(at time: TimeInterval) -> Frame {
        let base = time * speed
        return Frame { r, c in RGB(hue: base + Double(c) * 16 + Double(r) * 6) }
    }
}

// MARK: - Solid frame

public final class StillAnimation: Animation {
    let still: Frame
    public init(_ frame: Frame) { still = frame }
    public func frame(at time: TimeInterval) -> Frame { still }
}
