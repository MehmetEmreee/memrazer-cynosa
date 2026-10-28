// SPDX-License-Identifier: GPL-2.0-or-later
// Razer Chroma protocol as used by the Cynosa V2 (1532:025E).
// Reference: OpenRazer driver/razerkbd_driver.c, driver/razerchromacommon.c.

public enum Cynosa {
    public static let vendorID = 0x1532
    public static let productID = 0x025E
    public static let rows = 6
    public static let columns = 22
}

public struct RGB: Hashable, Codable, Sendable {
    public var r, g, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "%02X%02X%02X", r, g, b) }

    public init(hue: Double, saturation: Double = 1, value: Double = 1) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = value * saturation
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h / 60) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(UInt8(((r + m) * 255).rounded()), UInt8(((g + m) * 255).rounded()), UInt8(((b + m) * 255).rounded()))
    }
}

public enum CommandStatus: UInt8, Sendable {
    case new = 0x00, busy = 0x01, success = 0x02, failure = 0x03, timeout = 0x04, notSupported = 0x05
}

/// 90-byte feature report:
/// status · transaction · remaining(2, BE) · protocol · size · class · id · args[80] · crc · reserved
public struct RazerReport: Equatable, Sendable {
    public static let length = 90
    public private(set) var bytes: [UInt8]

    public init(commandClass: UInt8, commandID: UInt8, dataSize: UInt8, transaction: UInt8 = 0x1F) {
        bytes = [UInt8](repeating: 0, count: Self.length)
        bytes[1] = transaction
        bytes[5] = dataSize
        bytes[6] = commandClass
        bytes[7] = commandID
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.length else { return nil }
        self.bytes = bytes
    }

    public var status: CommandStatus? { CommandStatus(rawValue: bytes[0]) }
    public var transaction: UInt8 { bytes[1] }
    public var dataSize: UInt8 { bytes[5] }
    public var commandClass: UInt8 { bytes[6] }
    public var commandID: UInt8 { bytes[7] }
    public var crc: UInt8 { bytes[88] }

    public subscript(arg i: Int) -> UInt8 {
        get { bytes[8 + i] }
        set { bytes[8 + i] = newValue }
    }

    public mutating func set(_ c: RGB, at i: Int) {
        self[arg: i] = c.r; self[arg: i + 1] = c.g; self[arg: i + 2] = c.b
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes[2..<88].reduce(0, ^)
    }

    public func sealed() -> RazerReport {
        var copy = self
        copy.bytes[88] = Self.checksum(bytes)
        return copy
    }

    public func answers(_ request: RazerReport) -> Bool {
        commandClass == request.commandClass && commandID == request.commandID
    }
}

public enum WaveDirection: UInt8, Codable, CaseIterable, Sendable { case left = 0, right = 1 }

/// Pure builders; no I/O.
public enum Command {
    static let varstore: UInt8 = 0x01
    static let backlight: UInt8 = 0x05
    static let gameLED: UInt8 = 0x08

    public static func firmware() -> RazerReport {
        RazerReport(commandClass: 0x00, commandID: 0x81, dataSize: 0x02, transaction: 0xFF)
    }

    public static func serial() -> RazerReport {
        RazerReport(commandClass: 0x00, commandID: 0x82, dataSize: 0x16, transaction: 0xFF)
    }

    public static func deviceMode(driver: Bool) -> RazerReport {
        var r = RazerReport(commandClass: 0x00, commandID: 0x04, dataSize: 0x02, transaction: 0xFF)
        r[arg: 0] = driver ? 0x03 : 0x00
        return r
    }

    public static func setGameMode(_ on: Bool) -> RazerReport {
        var r = RazerReport(commandClass: 0x03, commandID: 0x00, dataSize: 0x03, transaction: 0xFF)
        r[arg: 0] = varstore; r[arg: 1] = gameLED; r[arg: 2] = on ? 1 : 0
        return r
    }

    public static func getGameMode() -> RazerReport {
        var r = RazerReport(commandClass: 0x03, commandID: 0x80, dataSize: 0x03, transaction: 0xFF)
        r[arg: 0] = varstore; r[arg: 1] = gameLED
        return r
    }

    public static func setBrightness(_ value: UInt8) -> RazerReport {
        var r = RazerReport(commandClass: 0x0F, commandID: 0x04, dataSize: 0x03)
        r[arg: 0] = varstore; r[arg: 1] = backlight; r[arg: 2] = value
        return r
    }

    public static func getBrightness() -> RazerReport {
        var r = RazerReport(commandClass: 0x0F, commandID: 0x84, dataSize: 0x03)
        r[arg: 0] = varstore; r[arg: 1] = backlight
        return r
    }

    private static func effect(_ id: UInt8, size: UInt8) -> RazerReport {
        var r = RazerReport(commandClass: 0x0F, commandID: 0x02, dataSize: size)
        r[arg: 0] = varstore; r[arg: 1] = backlight; r[arg: 2] = id
        return r
    }

    public static func off() -> RazerReport { effect(0x00, size: 0x06) }

    public static func staticColor(_ c: RGB) -> RazerReport {
        var r = effect(0x01, size: 0x09)
        r[arg: 5] = 0x01; r.set(c, at: 6)
        return r
    }

    public static func breathing(_ colors: [RGB]) -> RazerReport {
        switch colors.count {
        case 0:
            return effect(0x02, size: 0x06)
        case 1:
            var r = effect(0x02, size: 0x09)
            r[arg: 3] = 0x01; r[arg: 5] = 0x01; r.set(colors[0], at: 6)
            return r
        default:
            var r = effect(0x02, size: 0x0C)
            r[arg: 3] = 0x02; r[arg: 5] = 0x02; r.set(colors[0], at: 6); r.set(colors[1], at: 9)
            return r
        }
    }

    public static func spectrum() -> RazerReport { effect(0x03, size: 0x06) }

    /// speed: lower is faster; OpenRazer default 0x28.
    public static func wave(_ direction: WaveDirection, speed: UInt8 = 0x28) -> RazerReport {
        var r = effect(0x04, size: 0x06)
        r[arg: 3] = direction.rawValue; r[arg: 4] = max(1, speed)
        return r
    }

    /// speed 1…4
    public static func reactive(_ c: RGB, speed: UInt8) -> RazerReport {
        var r = effect(0x05, size: 0x09)
        r[arg: 4] = min(max(speed, 1), 4); r[arg: 5] = 0x01; r.set(c, at: 6)
        return r
    }

    /// speed 1…3
    public static func starlight(_ colors: [RGB], speed: UInt8) -> RazerReport {
        let s = min(max(speed, 1), 3)
        switch colors.count {
        case 0:
            var r = effect(0x07, size: 0x06)
            r[arg: 4] = s
            return r
        case 1:
            var r = effect(0x07, size: 0x09)
            r[arg: 4] = s; r[arg: 5] = 0x01; r.set(colors[0], at: 6)
            return r
        default:
            var r = effect(0x07, size: 0x0C)
            r[arg: 4] = s; r[arg: 5] = 0x02; r.set(colors[0], at: 6); r.set(colors[1], at: 9)
            return r
        }
    }

    /// Inclusive column range; at most 25 LEDs per packet.
    public static func frameRow(_ row: Int, start: Int = 0, colors: ArraySlice<RGB>) -> RazerReport {
        precondition((0..<Cynosa.rows).contains(row))
        precondition(start >= 0 && !colors.isEmpty && start + colors.count <= Cynosa.columns)
        var r = RazerReport(commandClass: 0x0F, commandID: 0x03, dataSize: 0x47)
        r[arg: 2] = UInt8(row)
        r[arg: 3] = UInt8(start)
        r[arg: 4] = UInt8(start + colors.count - 1)
        for (i, c) in colors.enumerated() { r.set(c, at: 5 + i * 3) }
        return r
    }

    public static func showCustomFrame() -> RazerReport {
        var r = RazerReport(commandClass: 0x0F, commandID: 0x02, dataSize: 0x0C)
        r[arg: 2] = 0x08
        return r
    }
}
