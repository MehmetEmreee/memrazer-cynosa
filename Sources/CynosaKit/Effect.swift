// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public enum Effect: Codable, Equatable, Sendable {
    // On-device (keeps running without the app)
    case off
    case staticColor(RGB)
    case breathing([RGB])
    case spectrum
    case wave(WaveDirection, speed: UInt8)
    case reactive(RGB, speed: UInt8)
    case starlight([RGB], speed: UInt8)
    // Host-rendered (needs the app/CLI running)
    case fire(FirePalette, intensity: Double)
    case rainbow(speed: Double)
    case gif(path: String, mode: ScaleMode, speed: Double, vivid: Bool)
    case sky(cloudiness: Double, timeLapse: Bool, planes: Bool)

    public var isHostRendered: Bool {
        switch self {
        case .fire, .rainbow, .gif, .sky: return true
        default: return false
        }
    }

    public var hardwareCommand: RazerReport? {
        switch self {
        case .off: return Command.off()
        case .staticColor(let c): return Command.staticColor(c)
        case .breathing(let cs): return Command.breathing(cs)
        case .spectrum: return Command.spectrum()
        case .wave(let d, let s): return Command.wave(d, speed: s)
        case .reactive(let c, let s): return Command.reactive(c, speed: s)
        case .starlight(let cs, let s): return Command.starlight(cs, speed: s)
        case .fire, .rainbow, .gif, .sky: return nil
        }
    }

    public func makeAnimation() throws -> Animation? {
        switch self {
        case .fire(let p, let i): return FireAnimation(palette: p, intensity: i)
        case .rainbow(let s): return RainbowAnimation(speed: s)
        case .gif(let path, let mode, let speed, let vivid):
            let a = try GIFAnimation(url: URL(fileURLWithPath: path), mode: mode, vivid: vivid)
            a.speed = speed
            return a
        case .sky(let clouds, let fast, let planes): return SkyAnimation(cloudiness: clouds, timeLapse: fast, planes: planes)
        default: return nil
        }
    }
}

/// Applies effects to a keyboard, owning the player for host-rendered ones.
public final class EffectEngine: @unchecked Sendable {
    public private(set) var player: AnimationPlayer?
    public var fps: Double = 30

    public init() {}

    public func apply(_ effect: Effect, to keyboard: Keyboard?,
                      onFrame: ((Frame) -> Void)? = nil,
                      onError: ((Error) -> Void)? = nil) throws {
        player?.stop()
        player = nil
        if let cmd = effect.hardwareCommand {
            try keyboard?.send(cmd)
            return
        }
        guard let animation = try effect.makeAnimation() else { return }
        let p = AnimationPlayer(animation: animation, keyboard: keyboard, fps: fps)
        p.onFrame = onFrame
        p.onError = onError
        player = p
        p.start()
    }

    public func stop() {
        player?.stop()
        player = nil
    }
}
