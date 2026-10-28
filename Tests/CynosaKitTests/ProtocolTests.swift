// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CynosaKit

final class ProtocolTests: XCTestCase {
    func testHeaderLayout() {
        let r = Command.staticColor(RGB(0xFF, 0x80, 0x01))
        XCTAssertEqual(Array(r.bytes[0..<8]), [0x00, 0x1F, 0x00, 0x00, 0x00, 0x09, 0x0F, 0x02])
        XCTAssertEqual(Array(r.bytes[8..<17]), [0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x80, 0x01])
        XCTAssertEqual(r.bytes.count, 90)
    }

    func testChecksumIsXorOfBytes2Through87() {
        let r = Command.staticColor(RGB(0xFF, 0x00, 0x00)).sealed()
        // 0x09 ^ 0x0F ^ 0x02 ^ 0x01 ^ 0x05 ^ 0x01 ^ 0x01 ^ 0xFF
        XCTAssertEqual(r.crc, 0x09 ^ 0x0F ^ 0x02 ^ 0x01 ^ 0x05 ^ 0x01 ^ 0x01 ^ 0xFF)
        XCTAssertEqual(r.bytes[89], 0)
    }

    func testStandardCommandsUseTransactionFF() {
        XCTAssertEqual(Command.firmware().transaction, 0xFF)
        XCTAssertEqual(Command.setGameMode(true).transaction, 0xFF)
        XCTAssertEqual(Command.setGameMode(true)[arg: 2], 1)
    }

    func testBreathingVariants() {
        XCTAssertEqual(Command.breathing([]).dataSize, 0x06)
        let one = Command.breathing([RGB(1, 2, 3)])
        XCTAssertEqual([one[arg: 3], one[arg: 5], one[arg: 6], one[arg: 7], one[arg: 8]], [1, 1, 1, 2, 3])
        let two = Command.breathing([RGB(1, 2, 3), RGB(4, 5, 6)])
        XCTAssertEqual(two.dataSize, 0x0C)
        XCTAssertEqual(Array(two.bytes[17..<20]), [4, 5, 6])
    }

    func testSpeedsAreClamped() {
        XCTAssertEqual(Command.reactive(.white, speed: 9)[arg: 4], 4)
        XCTAssertEqual(Command.starlight([], speed: 0)[arg: 4], 1)
        XCTAssertEqual(Command.wave(.left, speed: 0)[arg: 4], 1)
    }

    func testFrameRow() {
        let row = Frame(fill: RGB(10, 20, 30)).row(3)
        let r = Command.frameRow(3, colors: row)
        XCTAssertEqual(r.dataSize, 0x47)
        XCTAssertEqual([r[arg: 2], r[arg: 3], r[arg: 4]], [3, 0, 21])
        XCTAssertEqual(Array(r.bytes[13..<16]), [10, 20, 30])
        XCTAssertEqual(Array(r.bytes[(13 + 21 * 3)..<(16 + 21 * 3)]), [10, 20, 30])
        XCTAssertEqual(r[arg: 5 + 22 * 3], 0)
    }

    func testResponseMatching() {
        let req = Command.getBrightness()
        var bytes = req.bytes
        bytes[0] = CommandStatus.success.rawValue
        XCTAssertTrue(RazerReport(bytes: bytes)!.answers(req))
        bytes[7] = 0x04
        XCTAssertFalse(RazerReport(bytes: bytes)!.answers(req))
        XCTAssertNil(RazerReport(bytes: [0, 1]))
    }

    func testHex() {
        XCTAssertEqual(RGB(hex: "#ff8800"), RGB(255, 136, 0))
        XCTAssertNil(RGB(hex: "xyz"))
        XCTAssertEqual(RGB(255, 136, 0).hex, "FF8800")
    }
}

final class TransportTests: XCTestCase {
    func testKeyboardShowSendsSixRowsThenApply() throws {
        final class Recorder: ReportTransport {
            var sent: [RazerReport] = []
            func exchange(_ r: RazerReport) throws -> RazerReport { sent.append(r); return r }
        }
        let rec = Recorder()
        try Keyboard(transport: rec).show(Frame())
        XCTAssertEqual(rec.sent.count, 7)
        XCTAssertEqual(rec.sent.prefix(6).map { $0[arg: 2] }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(rec.sent.last, Command.showCustomFrame())
    }

    func testEffectRouting() {
        XCTAssertNotNil(Effect.spectrum.hardwareCommand)
        XCTAssertNil(Effect.fire(.classic, intensity: 0.5).hardwareCommand)
        XCTAssertTrue(Effect.rainbow(speed: 1).isHostRendered)
    }

    func testEffectCodableRoundTrip() throws {
        let e = Effect.gif(path: "/x.gif", mode: .fit, speed: 1.5, vivid: false)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(e)), e)
    }
}

final class AnimationTests: XCTestCase {
    func testFireProducesWarmBottomRow() {
        let fire = FireAnimation(palette: .classic, intensity: 1)
        let f = fire.frame(at: 2)
        let bottom = f.row(Frame.rows - 1)
        let avgRed = bottom.map { Int($0.r) }.reduce(0, +) / bottom.count
        let avgBlue = bottom.map { Int($0.b) }.reduce(0, +) / bottom.count
        XCTAssertGreaterThan(avgRed, 150)
        XCTAssertLessThan(avgBlue, avgRed)
    }

    func testGIFDecodeTimingAndDownsample() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cynosa-test.gif")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        for (color, delay) in [((255, 0, 0), 0.2), ((0, 0, 255), 0.5)] {
            let ctx = CGContext(data: nil, width: 44, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255, blue: CGFloat(color.2) / 255, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 44, height: 12))
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(dest, ctx.makeImage()!, props)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let gif = try GIFAnimation(url: url, vivid: false)
        XCTAssertEqual(gif.frames.count, 2)
        XCTAssertEqual(gif.duration, 0.7, accuracy: 0.01)
        XCTAssertGreaterThan(gif.frame(at: 0.1)[0, 0].r, 240)
        XCTAssertGreaterThan(gif.frame(at: 0.3)[5, 21].b, 240)
        XCTAssertGreaterThan(gif.frame(at: 0.75)[2, 10].r, 240) // loops
    }
}

final class DeltaTests: XCTestCase {
    final class Recorder: ReportTransport {
        var sent: [RazerReport] = []
        func exchange(_ r: RazerReport) throws -> RazerReport { sent.append(r); return r }
    }

    func testOnlyChangedRowsAreSent() throws {
        let rec = Recorder()
        let kb = Keyboard(transport: rec)
        var frame = Frame(fill: RGB(0, 0, 255))
        XCTAssertEqual(try kb.show(frame), 6)
        XCTAssertEqual(rec.sent.count, 7)

        XCTAssertEqual(try kb.show(frame), 0) // identical: nothing on the wire
        XCTAssertEqual(rec.sent.count, 7)

        frame[3, 5] = .white
        XCTAssertEqual(try kb.show(frame), 1)
        XCTAssertEqual(rec.sent.count, 9) // one row + apply
        XCTAssertEqual(rec.sent[7][arg: 2], 3)
    }

    func testEffectChangeForcesFullRewrite() throws {
        let rec = Recorder()
        let kb = Keyboard(transport: rec)
        let frame = Frame(fill: .white)
        try kb.show(frame)
        try kb.send(Command.spectrum())
        XCTAssertEqual(try kb.show(frame), 6)
    }

    func testBrightnessKeepsTheFrameCache() throws {
        let rec = Recorder()
        let kb = Keyboard(transport: rec)
        let frame = Frame(fill: .white)
        try kb.show(frame)
        try kb.setBrightness(100)
        XCTAssertEqual(try kb.show(frame), 0)
    }
}

