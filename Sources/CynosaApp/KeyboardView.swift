// SPDX-License-Identifier: GPL-2.0-or-later
import CynosaKit
import SwiftUI

struct KeyboardView: View {
    let frame: Frame

    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 4
            let cols = CGFloat(Frame.columns), rows = CGFloat(Frame.rows)
            let key = min((size.width - gap * (cols - 1)) / cols, (size.height - gap * (rows - 1)) / rows)
            let w = key * cols + gap * (cols - 1), h = key * rows + gap * (rows - 1)
            let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)

            func rect(_ r: Int, _ c: Int) -> CGRect {
                CGRect(x: origin.x + CGFloat(c) * (key + gap), y: origin.y + CGFloat(r) * (key + gap), width: key, height: key)
            }

            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: key * 0.6))
                glow.opacity = 0.7
                for r in 0..<Frame.rows {
                    for c in 0..<Frame.columns {
                        glow.fill(Path(rect(r, c).insetBy(dx: -2, dy: -2)), with: .color(frame[r, c].color))
                    }
                }
            }
            for r in 0..<Frame.rows {
                for c in 0..<Frame.columns {
                    let p = Path(roundedRect: rect(r, c), cornerRadius: key * 0.22)
                    ctx.fill(p, with: .color(Color(white: 0.09)))
                    ctx.fill(p, with: .color(frame[r, c].color.opacity(0.92)))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 1)
                }
            }
        }
        .drawingGroup()
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8((ns.redComponent * 255).rounded()),
                  UInt8((ns.greenComponent * 255).rounded()),
                  UInt8((ns.blueComponent * 255).rounded()))
    }
}

extension Binding where Value == RGB {
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGB($0) })
    }
}
