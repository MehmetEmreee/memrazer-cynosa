// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Low-precision lunar position and phase (Astronomical Almanac / Meeus terms, as used by suncalc).
/// Accurate to about a degree, which is far finer than one key.
public struct MoonPosition: Equatable, Sendable {
    /// Degrees above the horizon.
    public var elevation: Double
    /// Hour angle in degrees, −180…180: negative while rising, positive while setting.
    public var hourAngle: Double
    /// Hour angle of moonrise / moonset (±); 180 if it never sets, 0 if it never rises.
    public var halfDay: Double
    /// Highest elevation the moon reaches today.
    public var transitElevation: Double
    /// 0 new · 0.25 first quarter · 0.5 full · 0.75 last quarter.
    public var phase: Double
    /// Illuminated fraction of the disc, 0…1.
    public var illumination: Double

    public var isWaxing: Bool { phase < 0.5 }

    public init(date: Date, latitude: Double, longitude: Double) {
        let rad = Double.pi / 180
        let obliquity = 23.4397 * rad
        let d = date.timeIntervalSince1970 / 86400 - 10957.5 // days since J2000.0

        func equatorial(_ l: Double, _ b: Double) -> (ra: Double, dec: Double) {
            (atan2(sin(l) * cos(obliquity) - tan(b) * sin(obliquity), cos(l)),
             asin(sin(b) * cos(obliquity) + cos(b) * sin(obliquity) * sin(l)))
        }

        // Moon
        let L = (218.316 + 13.176396 * d) * rad
        let M = (134.963 + 13.064993 * d) * rad
        let F = (93.272 + 13.229350 * d) * rad
        let moon = equatorial(L + 6.289 * rad * sin(M), 5.128 * rad * sin(F))
        let moonDistance = 385001 - 20905 * cos(M) // km

        // Sun (for the phase)
        let sm = (357.5291 + 0.98560028 * d) * rad
        let center = (1.9148 * sin(sm) + 0.02 * sin(2 * sm) + 0.0003 * sin(3 * sm)) * rad
        let sun = equatorial(sm + center + 102.9372 * rad + .pi, 0)
        let sunDistance = 149_598_000.0

        // Horizon coordinates
        let phi = latitude * rad
        let sidereal = (280.16 + 360.9856235 * d) * rad + longitude * rad
        var h = (sidereal - moon.ra).truncatingRemainder(dividingBy: 2 * .pi)
        if h > .pi { h -= 2 * .pi }
        if h < -.pi { h += 2 * .pi }
        elevation = asin(sin(phi) * sin(moon.dec) + cos(phi) * cos(moon.dec) * cos(h)) / rad
        hourAngle = h / rad

        let x = -tan(phi) * tan(moon.dec)
        halfDay = x <= -1 ? 180 : (x >= 1 ? 0 : acos(x) / rad)
        transitElevation = 90 - abs(latitude - moon.dec / rad)

        // Phase
        let elongation = acos(sin(sun.dec) * sin(moon.dec) + cos(sun.dec) * cos(moon.dec) * cos(sun.ra - moon.ra))
        let inc = atan2(sunDistance * sin(elongation), moonDistance - sunDistance * cos(elongation))
        let angle = atan2(cos(sun.dec) * sin(sun.ra - moon.ra),
                          sin(sun.dec) * cos(moon.dec) - cos(sun.dec) * sin(moon.dec) * cos(sun.ra - moon.ra))
        illumination = (1 + cos(inc)) / 2
        phase = 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / .pi
    }
}
