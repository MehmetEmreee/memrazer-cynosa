// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// NOAA low-precision solar position (±0.5°), good enough for a keyboard sky.
public struct SolarPosition: Equatable, Sendable {
    /// Degrees above the horizon.
    public var elevation: Double
    /// Hour angle in degrees: negative before solar noon, positive after.
    public var hourAngle: Double
    /// Hour angle of sunrise / sunset (±); 180 for midnight sun, 0 for polar night.
    public var halfDay: Double
    /// Elevation at solar noon.
    public var noonElevation: Double

    public init(date: Date, latitude: Double, longitude: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .hour, .minute, .second], from: date)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let isLeap = cal.range(of: .day, in: .year, for: date)?.count == 366

        let rad = Double.pi / 180
        let g = 2 * .pi / (isLeap ? 366 : 365) * (dayOfYear - 1 + (hour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
                               - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
                 + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)

        let trueSolarMinutes = hour * 60 + eqTime + 4 * longitude
        var ha = trueSolarMinutes / 4 - 180
        ha = (ha + 540).truncatingRemainder(dividingBy: 360) - 180

        let lat = latitude * rad
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha * rad)
        elevation = 90 - acos(min(max(cosZenith, -1), 1)) / rad
        hourAngle = ha

        let x = -tan(lat) * tan(decl)
        halfDay = x <= -1 ? 180 : (x >= 1 ? 0 : acos(x) / rad)
        noonElevation = 90 - abs(latitude - decl / rad)
    }
}

/// Real-time sky: the sun rises on the right (east), arcs over the keys and sets on the left (west);
/// the sky colour follows its elevation, clouds drift across both ways, an airliner passes now and
/// then and at night the moon (real position and phase) rises among twinkling stars.
///
/// Colours are authored for RGB LEDs, not screens: pastels wash out to white on LEDs and soft
/// gradients turn to mush at 22×6, so the palette uses saturated primaries (blue sky with no red,
/// orange sun, pure-white clouds), edges are sharpened and clouds get a dark outline.
public final class SkyAnimation: Animation {
    public var latitude: Double
    public var longitude: Double
    public var cloudiness: Double
    /// One simulated day every two minutes.
    public var timeLapse: Bool
    /// Simulated seconds per real second in time-lapse; 720 = one day every two minutes.
    /// Only the sun, moon and sky colour speed up; clouds and planes keep their real pace.
    public var timeLapseRate: Double = 720
    public var planes: Bool

    private let clock: () -> Date
    private var origin: Date?
    private var clouds: [Cloud] = []
    private var plane: Plane?
    private var nextPlane: TimeInterval?
    private var lastTime: TimeInterval?
    private var now: TimeInterval = 0
    private var darkness: Double = 0 // 0 day … 1 night
    private lazy var stars: [Star] = makeStars()

    struct Star {
        var row, column: Int
        var phase, rate, brightness: Double
    }
    private var rng: RandomNumberGenerator

    struct Cloud {
        var x: Double
        var y: Double
        var speed: Double // keys per second, sign is direction
        var puffs: [Puff]
        var halfWidth: Double { puffs.map { abs($0.dx) + $0.rx }.max() ?? 1 }
    }

    struct Puff {
        var dx, dy, rx, ry: Double
    }

    enum CloudShape: CaseIterable {
        case cumulus, stratus, puff, twin, tower
    }

    struct Plane {
        var x: Double     // nose position
        var y: Double     // row; fixed for the whole pass
        var speed: Double // keys per second, sign is direction
        /// Nose to tail; the rows above and below the middle key hold the wings.
        static let length = 5
        static let ceiling = 1.0, floor = 4.0 // keeps the wings on the grid

        /// Straight and level: once on screen a plane never changes altitude.
        mutating func step(_ dt: TimeInterval) {
            x += speed * dt
        }

        var row: Int { Int(y.rounded()) }
    }

    public init(cloudiness: Double = 0.5, timeLapse: Bool = false, planes: Bool = true,
                latitude: Double = 41.01, longitude: Double = 28.98,
                clock: @escaping () -> Date = Date.init,
                rng: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.cloudiness = cloudiness
        self.timeLapse = timeLapse
        self.planes = planes
        self.latitude = latitude
        self.longitude = longitude
        self.clock = clock
        self.rng = rng
    }

    // MARK: Frame

    /// 60 fps while a plane is on screen and in time-lapse; 15 fps is plenty for drifting clouds,
    /// and unchanged rows are skipped by `Keyboard.show` anyway.
    public var preferredFPS: Double? { timeLapse || plane != nil ? 60 : 15 }

    /// True while an airliner is on screen.
    public var hasPlane: Bool { plane != nil }

    public func frame(at time: TimeInterval) -> Frame {
        let date = clock()
        if origin == nil { origin = date }
        let simulated = timeLapse ? origin!.addingTimeInterval(time * timeLapseRate) : date
        let sun = SolarPosition(date: simulated, latitude: latitude, longitude: longitude)
        let moon = MoonPosition(date: simulated, latitude: latitude, longitude: longitude)
        let dt = lastTime.map { min(max(time - $0, 0), 0.5) } ?? 0
        lastTime = time
        now = time
        advanceClouds(dt)
        advancePlane(dt, at: time)
        return render(sun, moon: moon)
    }

    public func render(_ sun: SolarPosition, moon: MoonPosition? = nil) -> Frame {
        let palette = Self.skyPalette(sun.elevation)
        let sunBlock = sunPosition(sun).map(Self.sunBlock)
        darkness = Self.smoothstep(2, -4, sun.elevation)
        let sunColor = Self.sunColor(sun.elevation)
        let cloudColor = Self.cloudColor(sun.elevation, palette)
        let rows = Double(Frame.rows - 1)
        let moonBlock = moon.flatMap { darkness > 0.4 ? moonPosition($0) : nil }.map(Self.sunBlock)
        let moonColumns = moon.map(Self.moonColumns) ?? (left: 0, right: 0)

        // 3×3 coverage per key, then sharpened so shapes read as solid blocks on LEDs.
        let sub = [-1.0 / 3, 0, 1.0 / 3]
        func covered(_ r: Int, _ c: Int, _ inside: (Double, Double) -> Bool) -> Double {
            var n = 0
            for oy in sub { for ox in sub where inside(Double(c) + ox, Double(r) + oy) { n += 1 } }
            return Self.smoothstep(0.2, 0.75, Double(n) / 9)
        }

        var cloud = [Double](repeating: 0, count: Frame.rows * Frame.columns)
        if !clouds.isEmpty {
            for r in 0..<Frame.rows {
                for c in 0..<Frame.columns {
                    cloud[r * Frame.columns + c] = covered(r, c) { x, y in self.clouds.contains { Self.inside($0, x, y) } }
                }
            }
        }
        func cloudAt(_ r: Int, _ c: Int) -> Double {
            guard (0..<Frame.rows).contains(r), (0..<Frame.columns).contains(c) else { return 0 }
            return cloud[r * Frame.columns + c]
        }

        return Frame { r, c in
            var px = Self.mix(palette.top, palette.bottom, Double(r) / rows)

            // Outline: darken open sky right next to a cloud.
            let own = cloudAt(r, c)
            if own < 0.3 {
                let near = max(cloudAt(r - 1, c), cloudAt(r + 1, c), cloudAt(r, c - 1), cloudAt(r, c + 1))
                if near > 0.6 { px = Self.mix(px, Self.c(0, 0, 0), 0.55) }
            }

            var inMoon = false
            if let m = moonBlock, (m.row...m.row + 1).contains(r), (m.col...m.col + 1).contains(c) {
                inMoon = true
                let lit = c == m.col ? moonColumns.left : moonColumns.right
                px = Self.mix(Self.earthshine, Self.moonColor, lit)
            }
            if !inMoon, darkness > 0.6, let star = stars.first(where: { $0.row == r && $0.column == c }) {
                let twinkle = 0.55 + 0.45 * sin(now * star.rate + star.phase)
                px = Self.mix(px, Self.starColor, star.brightness * twinkle * (darkness - 0.6) / 0.4)
            }

            if let block = sunBlock, (block.row...block.row + 1).contains(r), (block.col...block.col + 1).contains(c) {
                px = sunColor
            }

            // Airliners cruise above most clouds, so clouds pass in front of them.
            if let plane, let color = self.planePixel(plane, c, r) { px = color }

            if own > 0 { px = Self.mix(px, cloudColor, own) }

            return RGB(UInt8(min(255, max(0, px.0 * 255)).rounded()),
                       UInt8(min(255, max(0, px.1 * 255)).rounded()),
                       UInt8(min(255, max(0, px.2 * 255)).rounded()))
        }
    }

    /// Key-space position of the sun, or nil once it is below the horizon.
    func sunPosition(_ sun: SolarPosition) -> (x: Double, y: Double)? {
        guard sun.elevation > -2, sun.halfDay > 0 else { return nil }
        let progress = min(max((sun.hourAngle + sun.halfDay) / (2 * sun.halfDay), 0), 1) // 0 sunrise … 1 sunset
        let x = Double(Frame.columns - 1) * (1 - progress)
        let peak = max(sun.noonElevation, 1)
        let height = min(max(sun.elevation / peak, -0.2), 1)
        let y = Double(Frame.rows - 1) + 0.5 - height * (Double(Frame.rows - 1) - 0.2)
        return (x, y)
    }

    /// The sun is always a solid 2×2 block (4 keys) kept fully on the grid.
    static func sunBlock(_ pos: (x: Double, y: Double)) -> (row: Int, col: Int) {
        let col = min(max(Int((pos.x - 0.5).rounded(.down)), 0), Frame.columns - 2)
        let row = min(max(Int((pos.y - 0.5).rounded(.down)), 0), Frame.rows - 2)
        return (row, col)
    }

    /// Same mapping as the sun: rises on the right, sets on the left.
    func moonPosition(_ moon: MoonPosition) -> (x: Double, y: Double)? {
        guard moon.elevation > -1, moon.halfDay > 0 else { return nil }
        let progress = min(max((moon.hourAngle + moon.halfDay) / (2 * moon.halfDay), 0), 1)
        let x = Double(Frame.columns - 1) * (1 - progress)
        let height = min(max(moon.elevation / max(moon.transitElevation, 1), -0.2), 1)
        let y = Double(Frame.rows - 1) + 0.5 - height * (Double(Frame.rows - 1) - 0.2)
        return (x, y)
    }

    /// Lit amount of the moon's left and right key columns. Northern hemisphere: a waxing moon is lit
    /// on the right, a waning one on the left; one column for a crescent/half, both when near full.
    static func moonColumns(_ moon: MoonPosition) -> (left: Double, right: Double) {
        let near = min(1, moon.illumination * 2)
        let far = max(0, moon.illumination * 2 - 1)
        return moon.isWaxing ? (far, near) : (near, far)
    }

    private func makeStars() -> [Star] {
        var cells = Set<Int>()
        while cells.count < 12 {
            cells.insert(Int.random(in: 0..<(4 * Frame.columns), using: &rng))
        }
        return cells.map {
            Star(row: $0 / Frame.columns, column: $0 % Frame.columns,
                 phase: Double.random(in: 0..<(2 * .pi), using: &rng),
                 rate: Double.random(in: 1.5...4, using: &rng),
                 brightness: Double.random(in: 0.5...1, using: &rng))
        }
    }

    // MARK: Clouds

    private var targetCount: Int { Int((cloudiness * 5).rounded()) }

    private func advanceClouds(_ dt: TimeInterval) {
        if clouds.isEmpty {
            for _ in 0..<targetCount { clouds.append(makeCloud(onScreen: true)) }
        }
        let width = Double(Frame.columns)
        for i in clouds.indices { clouds[i].x += clouds[i].speed * dt }
        clouds.removeAll { cl in
            (cl.speed > 0 && cl.x - cl.halfWidth > width) || (cl.speed < 0 && cl.x + cl.halfWidth < -1)
        }
        while clouds.count > targetCount { clouds.removeLast() }
        if clouds.count < targetCount, Double.random(in: 0..<1, using: &rng) < dt * 0.8 {
            clouds.append(makeCloud(onScreen: false))
        }
    }

    private func makeCloud(onScreen: Bool) -> Cloud {
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        let fromLeft = Bool.random(using: &rng)
        let speed = r(0.5...1.3) * (fromLeft ? 1 : -1)
        let shape = CloudShape.allCases.randomElement(using: &rng)!

        var puffs: [Puff]
        switch shape {
        case .cumulus: // flat base, one or two domes on top
            puffs = [Puff(dx: 0, dy: 0.35, rx: r(2.2...3.0), ry: 0.7)]
            for _ in 0..<Int.random(in: 1...2, using: &rng) {
                puffs.append(Puff(dx: r(-1.2...1.2), dy: -0.4, rx: r(1.0...1.4), ry: r(0.8...1.0)))
            }
        case .stratus: // long, one row tall
            puffs = [Puff(dx: 0, dy: 0, rx: r(3.5...5.0), ry: 0.6)]
            if Bool.random(using: &rng) { puffs.append(Puff(dx: r(-2...2), dy: -0.3, rx: 1.2, ry: 0.6)) }
        case .puff: // small, two or three keys
            puffs = [Puff(dx: 0, dy: 0, rx: r(1.1...1.6), ry: r(0.65...0.85))]
        case .twin: // two small clouds flying together
            let gap = r(2.3...3.2)
            puffs = [Puff(dx: -gap / 2, dy: r(-0.3...0.3), rx: r(1.0...1.4), ry: 0.7),
                     Puff(dx: gap / 2, dy: r(-0.3...0.3), rx: r(1.0...1.4), ry: 0.7)]
        case .tower: // tall cumulonimbus
            puffs = [Puff(dx: 0, dy: 0.7, rx: r(2.2...2.8), ry: 0.6),
                     Puff(dx: r(-0.4...0.4), dy: -0.3, rx: r(1.2...1.5), ry: r(1.4...1.7))]
        }

        let top = puffs.map { $0.dy - $0.ry }.min()!, bottom = puffs.map { $0.dy + $0.ry }.max()!
        let y = r(max(0.3, -top - 0.2)...(Double(Frame.rows) - 0.6 - bottom))
        var cloud = Cloud(x: 0, y: y, speed: speed, puffs: puffs)
        let half = cloud.halfWidth
        cloud.x = onScreen
            ? r(0...Double(Frame.columns - 1))
            : (fromLeft ? -half : Double(Frame.columns) + half)
        return cloud
    }

    static func inside(_ cl: Cloud, _ x: Double, _ y: Double) -> Bool {
        cl.puffs.contains {
            let u = (x - (cl.x + $0.dx)) / $0.rx, v = (y - (cl.y + $0.dy)) / $0.ry
            return u * u + v * v < 1
        }
    }

    // MARK: Plane

    private func advancePlane(_ dt: TimeInterval, at time: TimeInterval) {
        guard planes else { plane = nil; return }
        if nextPlane == nil { nextPlane = time + Double.random(in: 4...10, using: &rng) }
        if var p = plane {
            p.step(dt)
            let length = Double(Plane.length)
            let gone = p.speed > 0 ? p.x - length > Double(Frame.columns) : p.x + length < -1
            plane = gone ? nil : p
            if gone { nextPlane = time + Double.random(in: 15...35, using: &rng) }
        } else if let next = nextPlane, time >= next {
            plane = makePlane()
        }
    }

    /// Each plane cruises at its own altitude, picked before it enters.
    private func makePlane() -> Plane {
        let fromLeft = Bool.random(using: &rng)
        let speed = Double.random(in: 1.6...2.4, using: &rng)
        let row = Double(Int.random(in: Int(Plane.ceiling)...Int(Plane.floor), using: &rng))
        return Plane(x: fromLeft ? -0.5 : Double(Frame.columns) - 0.5, y: row,
                     speed: speed * (fromLeft ? 1 : -1))
    }

    enum PlanePart: Equatable { case nose, fuselage, wing, tail }

    /// Top-down airliner, a "T" lying on its side (shown flying right); nose and tail share a row:
    ///
    ///     . . W . .      W wing · = fuselage · N nose · T tail
    ///     T = = = N
    ///     . . W . .
    static func planePart(_ p: Plane, _ column: Int, _ row: Int) -> PlanePart? {
        let dir: Double = p.speed > 0 ? 1 : -1
        let k = Int(((p.x - Double(column)) * dir + 0.5).rounded(.down)) // 0 nose … length-1 tail
        guard (0..<Plane.length).contains(k) else { return nil }
        switch row - p.row {
        case 0: return k == 0 ? .nose : (k == Plane.length - 1 ? .tail : .fuselage)
        case -1, 1: return k == Plane.length / 2 ? .wing : nil
        default: return nil
        }
    }

    /// Day: white fuselage, grey wings. Night: unlit airframe with real aircraft lighting —
    /// white anti-collision strobes double-flashing on the wingtips every 1.3 s, a red beacon on
    /// the fuselage at 1 Hz and a steady white position light on the tail. No trail, no green.
    func planePixel(_ p: Plane, _ column: Int, _ row: Int) -> C? {
        guard let part = Self.planePart(p, column, row) else { return nil }
        if darkness <= 0.5 {
            return part == .wing ? Self.planeShade : Self.planeColor
        }
        let strobePhase = now.truncatingRemainder(dividingBy: 1.3)
        let strobe = strobePhase < 0.06 || (0.18..<0.24).contains(strobePhase)
        let beacon = now.truncatingRemainder(dividingBy: 1.0) < 0.15
        let k = Int(((p.x - Double(column)) * (p.speed > 0 ? 1 : -1) + 0.5).rounded(.down))
        switch part {
        case .wing where strobe: return Self.c(255, 255, 255)
        case .fuselage where k == Plane.length / 2 && beacon: return Self.c(255, 0, 0)
        case .tail: return Self.c(70, 70, 80)
        default: return nil // unlit airframe disappears into the night sky
        }
    }

    // MARK: Colour

    typealias C = (Double, Double, Double)

    static func c(_ r: Double, _ g: Double, _ b: Double) -> C { (r / 255, g / 255, b / 255) }
    func c(_ r: Double, _ g: Double, _ b: Double) -> C { Self.c(r, g, b) }

    static func mix(_ a: C, _ b: C, _ t: Double) -> C {
        let k = min(max(t, 0), 1)
        return (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k, a.2 + (b.2 - a.2) * k)
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// (elevation, zenith colour, horizon colour) in LED values; night is LEDs off.
    static let skyStops: [(Double, C, C)] = [
        (-10, c(0, 0, 0), c(0, 0, 0)),
        (-5, c(8, 0, 40), c(60, 0, 20)),
        (-1, c(40, 0, 140), c(255, 30, 0)),
        (3, c(20, 10, 200), c(255, 70, 0)),
        (9, c(0, 30, 255), c(120, 40, 160)),
        (15, c(0, 25, 255), c(0, 110, 255)),
        (90, c(0, 20, 255), c(0, 100, 255)),
    ]

    static func skyPalette(_ e: Double) -> (top: C, bottom: C) {
        if e <= skyStops[0].0 { return (skyStops[0].1, skyStops[0].2) }
        for i in 1..<skyStops.count where e <= skyStops[i].0 {
            let (e0, t0, b0) = skyStops[i - 1], (e1, t1, b1) = skyStops[i]
            let k = (e - e0) / (e1 - e0)
            return (mix(t0, t1, k), mix(b0, b1, k))
        }
        return (skyStops.last!.1, skyStops.last!.2)
    }

    /// Orange against the blue day sky (yellow vanishes next to blue); amber near the horizon so it
    /// still stands out from the red-orange dusk glow behind it.
    static func sunColor(_ e: Double) -> C {
        mix(c(255, 150, 10), c(255, 95, 0), smoothstep(0, 12, e))
    }

    static let planeColor = c(225, 230, 240)
    static let planeShade = c(130, 135, 150)
    static let moonColor = c(210, 200, 150)
    static let earthshine = c(6, 6, 9)
    static let starColor = c(150, 150, 175)

    static func cloudColor(_ e: Double, _ sky: (top: C, bottom: C)) -> C {
        let day = c(255, 255, 255)
        let dusk = c(255, 90, 120)
        let night = c(12, 8, 20)
        if e > 6 { return day }
        if e > -1 { return mix(dusk, day, (e + 1) / 7) }
        return mix(night, dusk, max(0, (e + 7) / 6))
    }
}
