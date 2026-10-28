// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
@testable import CynosaKit

final class SkyTests: XCTestCase {
    let istanbul = (lat: 41.01, lon: 28.98)

    func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func sun(_ s: String) -> SolarPosition {
        SolarPosition(date: utc(s), latitude: istanbul.lat, longitude: istanbul.lon)
    }

    func testSummerSolsticeNoonIsHigh() {
        // Solar noon in Istanbul ≈ 10:10 UTC; max elevation ≈ 72.4°.
        let p = sun("2026-06-21T10:10:00Z")
        XCTAssertEqual(p.elevation, 72.4, accuracy: 1)
        XCTAssertEqual(p.hourAngle, 0, accuracy: 3)
    }

    func testMidnightIsBelowHorizon() {
        XCTAssertLessThan(sun("2026-06-21T22:00:00Z").elevation, -15)
    }

    func testWinterDayIsShorterThanSummer() {
        XCTAssertLessThan(sun("2026-12-21T10:00:00Z").halfDay, sun("2026-06-21T10:00:00Z").halfDay)
    }

    func testSunRisesOnTheRightAndSetsOnTheLeft() {
        let sky = SkyAnimation()
        let morning = sky.sunPosition(sun("2026-06-21T04:00:00Z"))! // ~07:00 local
        let evening = sky.sunPosition(sun("2026-06-21T16:30:00Z"))! // ~19:30 local
        let noon = sky.sunPosition(sun("2026-06-21T10:10:00Z"))!
        XCTAssertGreaterThan(morning.x, 15)
        XCTAssertLessThan(evening.x, 6)
        XCTAssertEqual(noon.x, Double(Frame.columns - 1) / 2, accuracy: 1.5)
        XCTAssertLessThan(noon.y, morning.y)
        XCTAssertNil(sky.sunPosition(sun("2026-06-21T22:00:00Z")))
    }

    func testDaySkyIsLightBlueAndNightIsOff() {
        let sky = SkyAnimation(cloudiness: 0)
        let day = sky.render(sun("2026-06-21T07:00:00Z"))
        let corner = day[Frame.rows - 1, 0] // far from the sun
        XCTAssertGreaterThan(corner.b, corner.r)
        XCTAssertGreaterThan(corner.b, 200)

        let night = sky.render(sun("2026-06-21T22:00:00Z"))
        XCTAssertGreaterThan(night.pixels.filter { $0 == .black }.count, 110) // only a few dim stars
        XCTAssertTrue(night.pixels.allSatisfy { max($0.r, $0.g, $0.b) < 180 })
    }

    func testCloudsDriftAndRespawn() {
        let date = utc("2026-06-21T10:00:00Z")
        let sky = SkyAnimation(cloudiness: 1, clock: { date })
        let a = sky.frame(at: 0)
        _ = sky.frame(at: 0.5)
        let b = sky.frame(at: 1.0)
        XCTAssertNotEqual(a, b)
        let whiteish = b.pixels.filter { $0.r > 200 && $0.g > 200 && $0.b > 200 }.count
        XCTAssertGreaterThan(whiteish, 0)
    }

    func testTimeLapseAdvancesTheSun() {
        let start = utc("2026-06-21T03:00:00Z")
        let sky = SkyAnimation(cloudiness: 0, timeLapse: true, clock: { start })
        let early = sky.frame(at: 0)
        let later = sky.frame(at: 30) // +6 h simulated
        XCTAssertNotEqual(early, later)
    }

    func testSunIsOrangeNotYellow() {
        let noon = SkyAnimation.sunColor(60)
        XCTAssertEqual(noon.0, 1)
        XCTAssertLessThan(noon.1, 0.45)
        XCTAssertEqual(noon.2, 0)
    }

    func testDaySkyHasNoRedSoWhiteCloudsStandOut() {
        let p = SkyAnimation.skyPalette(50)
        XCTAssertLessThan(p.top.0, 0.05)
        XCTAssertLessThan(p.bottom.0, 0.05)
    }

    func testCloudsGetADarkOutline() {
        let date = utc("2026-06-21T10:10:00Z")
        let sky = SkyAnimation(cloudiness: 1, planes: false, clock: { date })
        let f = sky.frame(at: 0)
        let palette = SkyAnimation.skyPalette(sun("2026-06-21T10:10:00Z").elevation)
        let darkest = f.pixels.map { Int($0.b) }.min()!
        XCTAssertLessThan(Double(darkest) / 255, palette.top.2 * 0.6)
    }

    func sunKeys(_ f: Frame, _ elevation: Double) -> Int {
        let c = SkyAnimation.sunColor(elevation)
        let rgb = RGB(UInt8((c.0 * 255).rounded()), UInt8((c.1 * 255).rounded()), UInt8((c.2 * 255).rounded()))
        return f.pixels.filter { $0 == rgb }.count
    }

    func testSunIsAlwaysFourKeys() {
        let sky = SkyAnimation(cloudiness: 0, planes: false)
        for time in ["2026-06-21T02:35:00Z", "2026-06-21T05:00:00Z", "2026-06-21T10:10:00Z", "2026-06-21T17:20:00Z"] {
            let p = sun(time)
            XCTAssertEqual(sunKeys(sky.render(p), p.elevation), 4, time)
        }
    }

    func testCloudsAlsoDriftLow() {
        let date = utc("2026-06-21T10:10:00Z")
        var lowRows = 0
        for _ in 0..<40 {
            let f = SkyAnimation(cloudiness: 1, planes: false, clock: { date }).frame(at: 0)
            for r in 3..<Frame.rows { lowRows += f.row(r).filter { $0 == .white }.count }
        }
        XCTAssertGreaterThan(lowRows, 0)
    }

    func planeColor() -> RGB {
        let c = SkyAnimation.planeColor
        return RGB(UInt8((c.0 * 255).rounded()), UInt8((c.1 * 255).rounded()), UInt8((c.2 * 255).rounded()))
    }

    func testDayPlaneIsPlainWithNoTrail() {
        let date = utc("2026-06-21T10:10:00Z")
        let sky = SkyAnimation(cloudiness: 0, clock: { date })
        let body = planeColor()
        var sawBody = false
        var t = 0.0
        while t < 40 {
            let f = sky.frame(at: t)
            let bodyKeys = f.pixels.filter { $0 == body }.count
            if bodyKeys > 0 { sawBody = true }
            XCTAssertLessThanOrEqual(bodyKeys, SkyAnimation.Plane.length)
            // Nothing orange/red/green beyond the sun's four keys.
            let warm = f.pixels.filter { $0.r > 200 && $0.b < 60 }.count
            XCTAssertLessThanOrEqual(warm, 4)
            XCTAssertFalse(f.pixels.contains { $0.g > 200 && $0.r < 80 && $0.b < 80 })
            t += 1.0 / 30
        }
        XCTAssertTrue(sawBody)
    }

    func testPlanesCanBeDisabled() {
        let date = utc("2026-06-21T10:10:00Z")
        let sky = SkyAnimation(cloudiness: 0, planes: false, clock: { date })
        var t = 0.0
        while t < 15 {
            XCTAssertFalse(sky.frame(at: t).pixels.contains(planeColor()))
            t += 0.25
        }
    }

    func testNightPlaneUsesRealLightingWithoutGreen() {
        let night = utc("2026-06-21T22:00:00Z")
        let sky = SkyAnimation(cloudiness: 0, clock: { night })
        var strobe = false, beacon = false
        var t = 0.0
        while t < 40 {
            let f = sky.frame(at: t)
            if f.pixels.contains(.white) { strobe = true }
            if f.pixels.contains(RGB(255, 0, 0)) { beacon = true }
            XCTAssertFalse(f.pixels.contains(RGB(0, 255, 0)))
            t += 1.0 / 30
        }
        XCTAssertTrue(strobe)
        XCTAssertTrue(beacon)
    }

    func testPlaneFliesStraightAndLevel() {
        var p = SkyAnimation.Plane(x: 0, y: 3, speed: 2)
        p.step(5)
        XCTAssertEqual(p.x, 10, accuracy: 1e-9)
        XCTAssertEqual(p.row, 3)
    }

    func testPlaneIsSlow() {
        let date = utc("2026-06-21T10:10:00Z")
        let sky = SkyAnimation(cloudiness: 0, clock: { date })
        let body = planeColor()
        var first: Double?, last = 0.0
        var t = 0.0
        while t < 40 {
            if sky.frame(at: t).pixels.contains(body) {
                if first == nil { first = t }
                last = t
            } else if first != nil { break }
            t += 1.0 / 30
        }
        XCTAssertNotNil(first)
        XCTAssertGreaterThan(last - first!, 8) // ≥22 keys at ≤2.4 keys/s
    }

    // MARK: Moon

    func moon(_ s: String) -> MoonPosition {
        MoonPosition(date: utc(s), latitude: istanbul.lat, longitude: istanbul.lon)
    }

    func testMoonPhases() {
        let full = moon("2026-01-03T10:00:00Z") // full moon 3 Jan 2026
        XCTAssertEqual(full.phase, 0.5, accuracy: 0.04)
        XCTAssertGreaterThan(full.illumination, 0.97)
        let new = moon("2026-01-18T20:00:00Z") // new moon 18 Jan 2026
        XCTAssertLessThan(new.illumination, 0.03)
        XCTAssertTrue(moon("2026-01-24T12:00:00Z").isWaxing)
        XCTAssertFalse(moon("2026-01-08T12:00:00Z").isWaxing)
    }

    func testFullMoonIsHighAtMidnight() {
        XCTAssertGreaterThan(moon("2026-01-03T22:00:00Z").elevation, 55)
        XCTAssertLessThan(moon("2026-01-03T10:00:00Z").elevation, 0)
    }

    func testMoonColumnsFollowPhase() {
        var m = moon("2026-01-24T12:00:00Z") // waxing crescent → lit on the right
        m.illumination = 0.3
        let crescent = SkyAnimation.moonColumns(m)
        XCTAssertEqual(crescent.left, 0)
        XCTAssertGreaterThan(crescent.right, 0.5)
        m.illumination = 1
        XCTAssertEqual(SkyAnimation.moonColumns(m).left, 1)
    }

    func testNightFrameShowsTheMoon() {
        let date = utc("2026-01-03T22:00:00Z")
        let sky = SkyAnimation(cloudiness: 0, planes: false, clock: { date })
        let f = sky.frame(at: 0)
        let moonish = f.pixels.filter { $0.r > 150 && $0.g > 150 && $0.b > 90 && $0.b < 200 }.count
        XCTAssertEqual(moonish, 4)
    }

    func testStarsTwinkleAtNight() {
        let date = utc("2026-01-18T22:00:00Z") // new moon, dark sky
        let sky = SkyAnimation(cloudiness: 0, planes: false, clock: { date })
        let a = sky.frame(at: 0), b = sky.frame(at: 0.4)
        XCTAssertGreaterThan(a.pixels.filter { $0 != .black }.count, 6)
        XCTAssertNotEqual(a, b)
    }

    // MARK: Plane shape and frame rate

    func testPlaneSilhouetteIsASidewaysTWithNoseAndTailLevel() {
        typealias Part = SkyAnimation.PlanePart
        func shape(_ p: SkyAnimation.Plane) -> [String: Part] {
            var out: [String: Part] = [:]
            for r in 0..<Frame.rows {
                for c in 0..<Frame.columns {
                    if let part = SkyAnimation.planePart(p, c, r) { out["\(r),\(c)"] = part }
                }
            }
            return out
        }
        let right = shape(SkyAnimation.Plane(x: 10, y: 2, speed: 2))
        XCTAssertEqual(right, ["2,10": .nose, "2,9": .fuselage, "2,8": .fuselage, "2,7": .fuselage, "2,6": .tail,
                               "1,8": .wing, "3,8": .wing])
        let left = shape(SkyAnimation.Plane(x: 10, y: 2, speed: -2))
        XCTAssertEqual(left["2,10"], .nose)
        XCTAssertEqual(left["2,14"], .tail)
        XCTAssertEqual(left["3,12"], .wing)
        XCTAssertEqual(left.count, 7)
    }

    func testFrameRateRisesForPlanesAndTimeLapse() {
        XCTAssertEqual(SkyAnimation(timeLapse: true).preferredFPS, 60)
        let date = utc("2026-06-21T10:10:00Z")
        let sky = SkyAnimation(cloudiness: 0.5, clock: { date })
        _ = sky.frame(at: 0)
        XCTAssertEqual(sky.preferredFPS, 15)
        var t = 0.0, sawFast = false
        while t < 40, !sawFast {
            _ = sky.frame(at: t)
            sawFast = sky.preferredFPS == 60
            t += 1.0 / 15
        }
        XCTAssertTrue(sawFast)
    }
}
