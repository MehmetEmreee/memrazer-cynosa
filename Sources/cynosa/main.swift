// SPDX-License-Identifier: GPL-2.0-or-later
import CynosaKit
import Foundation

let usage = """
usage: cynosa <command>
  info
  static <color>
  breathe [color [color]]
  spectrum
  wave [left|right] [speed]
  reactive <color> [1-4]
  starlight [color [color]] [-s 1-3]
  fire [classic|blue|green|purple]
  rainbow
  sky [clouds 0-1] [--fast] [--no-planes]
  gif <file> [fill|fit|stretch]
  brightness [0-100]
  game [on|off]
  off
  bench
"""

struct UsageError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

let names: [String: RGB] = [
    "red": RGB(255, 0, 0), "green": RGB(0, 255, 0), "blue": RGB(0, 0, 255), "white": .white,
    "yellow": RGB(255, 255, 0), "cyan": RGB(0, 255, 255), "magenta": RGB(255, 0, 255),
    "purple": RGB(128, 0, 255), "orange": RGB(255, 96, 0), "pink": RGB(255, 32, 128),
]

func color(_ s: String) throws -> RGB {
    if let c = names[s.lowercased()] ?? RGB(hex: s) { return c }
    throw UsageError(message: "invalid color: \(s)")
}

func percent(_ v: UInt8) -> Int { Int((Double(v) / 255 * 100).rounded()) }

func runForever(_ effect: Effect, _ kb: Keyboard) throws -> Never {
    let engine = EffectEngine()
    try engine.apply(effect, to: kb, onError: { err in
        FileHandle.standardError.write("cynosa: \(err.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    })
    signal(SIGINT) { _ in exit(0) }
    signal(SIGTERM) { _ in exit(0) }
    dispatchMain()
}

func run(_ args: [String]) throws {
    guard let cmd = args.first, !["-h", "--help", "help"].contains(cmd) else { print(usage); return }
    let rest = Array(args.dropFirst())
    let kb = try Keyboard.open()

    switch cmd {
    case "info":
        let i = try kb.info()
        print("firmware   \(i.firmware)")
        print("serial     \(i.serial)")
        print("brightness \(percent(try kb.brightness()))%")
        print("game mode  \(try kb.gameMode() ? "on" : "off")")
    case "static":
        guard let c = rest.first else { throw UsageError(message: "color required") }
        try kb.send(Command.staticColor(color(c)))
    case "breathe":
        try kb.send(Command.breathing(rest.prefix(2).map(color)))
    case "spectrum":
        try kb.send(Command.spectrum())
    case "wave":
        let dir: WaveDirection = rest.first == "left" ? .left : .right
        try kb.send(Command.wave(dir, speed: rest.count > 1 ? UInt8(rest[1]) ?? 0x28 : 0x28))
    case "reactive":
        guard let c = rest.first else { throw UsageError(message: "color required") }
        try kb.send(Command.reactive(color(c), speed: rest.count > 1 ? UInt8(rest[1]) ?? 2 : 2))
    case "starlight":
        var speed: UInt8 = 2, colors: [RGB] = []
        var it = rest.makeIterator()
        while let a = it.next() {
            if a == "-s" { speed = it.next().flatMap { UInt8($0) } ?? 2 } else { colors.append(try color(a)) }
        }
        try kb.send(Command.starlight(Array(colors.prefix(2)), speed: speed))
    case "off":
        try kb.send(Command.off())
    case "bench":
        // Alternate two frames so every row changes every time.
        let frames = [Frame(fill: RGB(255, 60, 0)), Frame(fill: RGB(0, 40, 255))]
        var start = Date(), n = 0
        while Date().timeIntervalSince(start) < 3 {
            try kb.show(frames[n % 2])
            n += 1
        }
        print(String(format: "full frames  %.1f fps max, %.2f ms/frame", Double(n) / 3, 3000 / Double(n)))

        let sky = SkyAnimation(cloudiness: 0.6)
        start = Date(); n = 0
        var rows = 0
        while Date().timeIntervalSince(start) < 6 {
            rows += try kb.show(sky.frame(at: Date().timeIntervalSince(start)))
            n += 1
            Thread.sleep(forTimeInterval: 1 / (sky.preferredFPS ?? 15))
        }
        print(String(format: "sky          %.1f fps, %.1f of 6 rows sent per frame", Double(n) / 6, Double(rows) / Double(n)))
    case "brightness":
        if let s = rest.first {
            guard let p = Double(s), (0...100).contains(p) else { throw UsageError(message: "brightness: 0-100") }
            try kb.setBrightness(UInt8((p / 100 * 255).rounded()))
        } else {
            print("\(percent(try kb.brightness()))%")
        }
    case "game":
        switch rest.first {
        case "on": try kb.setGameMode(true)
        case "off": try kb.setGameMode(false)
        default: print(try kb.gameMode() ? "on" : "off")
        }
    case "fire":
        let palette = rest.first.flatMap(FirePalette.init(rawValue:)) ?? .classic
        try runForever(.fire(palette, intensity: 0.7), kb)
    case "rainbow":
        try runForever(.rainbow(speed: 90), kb)
    case "sky":
        let clouds = rest.compactMap(Double.init).first ?? 0.5
        try runForever(.sky(cloudiness: min(max(clouds, 0), 1), timeLapse: rest.contains("--fast"), planes: !rest.contains("--no-planes")), kb)
    case "gif":
        guard let path = rest.first else { throw UsageError(message: "file required") }
        let mode = rest.count > 1 ? ScaleMode(rawValue: rest[1]) ?? .fill : .fill
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try runForever(.gif(path: url.path, mode: mode, speed: 1, vivid: true), kb)
    default:
        throw UsageError(message: "unknown command: \(cmd)\n\(usage)")
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write("cynosa: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
