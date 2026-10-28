// SPDX-License-Identifier: GPL-2.0-or-later
public struct Frame: Equatable, Sendable {
    public static let rows = Cynosa.rows
    public static let columns = Cynosa.columns

    public var pixels: [RGB]

    public init(fill: RGB = .black) {
        pixels = Array(repeating: fill, count: Self.rows * Self.columns)
    }

    public init(_ body: (_ row: Int, _ column: Int) -> RGB) {
        pixels = []
        pixels.reserveCapacity(Self.rows * Self.columns)
        for r in 0..<Self.rows {
            for c in 0..<Self.columns { pixels.append(body(r, c)) }
        }
    }

    public subscript(row: Int, column: Int) -> RGB {
        get { pixels[row * Self.columns + column] }
        set { pixels[row * Self.columns + column] = newValue }
    }

    public func row(_ r: Int) -> ArraySlice<RGB> {
        pixels[(r * Self.columns)..<((r + 1) * Self.columns)]
    }
}
