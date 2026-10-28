// SPDX-License-Identifier: GPL-2.0-or-later
import CynosaKit
import Foundation

/// Approximates on-device effects for the on-screen keyboard.
final class PreviewAnimation: Animation {
    private let effect: Effect
    private var stars: [Int: (start: Double, color: RGB)] = [:]
    private var lastSpawn = 0.0

    init(_ effect: Effect) { self.effect = effect }

    private static func scale(_ c: RGB, _ k: Double) -> RGB {
        RGB(UInt8(Double(c.r) * k), UInt8(Double(c.g) * k), UInt8(Double(c.b) * k))
    }

    func frame(at t: TimeInterval) -> Frame {
        switch effect {
        case .off:
            return Frame()
        case .staticColor(let c):
            return Frame(fill: c)
        case .breathing(let colors):
            let period = 4.0
            let cycle = Int(t / period)
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let k = 0.5 - 0.5 * cos(phase * 2 * .pi)
            let c = colors.isEmpty ? RGB(hue: Double(cycle) * 77) : colors[cycle % colors.count]
            return Frame(fill: Self.scale(c, k))
        case .spectrum:
            return Frame(fill: RGB(hue: t * 40))
        case .wave(let dir, let speed):
            let v = 260.0 / Double(max(speed, 1)) * 20
            let sign: Double = dir == .right ? -1 : 1
            return Frame { _, c in RGB(hue: Double(c) * 16 * sign + t * v) }
        case .reactive(let c, _):
            return Frame(fill: Self.scale(c, 0.08))
        case .starlight(let colors, let speed):
            let life = 1.6 / Double(speed)
            if t - lastSpawn > 0.08 {
                lastSpawn = t
                let key = Int.random(in: 0..<(Frame.rows * Frame.columns))
                let color = colors.isEmpty ? RGB(hue: .random(in: 0..<360)) : colors.randomElement()!
                stars[key] = (t, color)
            }
            stars = stars.filter { t - $0.value.start < life }
            var f = Frame()
            for (key, s) in stars {
                let p = (t - s.start) / life
                f.pixels[key] = Self.scale(s.color, sin(p * .pi))
            }
            return f
        case .fire, .rainbow, .gif, .sky:
            return Frame()
        }
    }
}
