import SwiftUI

struct MosaicPulsePlaceholderView: View {
    private struct Variant {
        let colorA: Color
        let colorB: Color
        let frequency: Double
        let speed: Double
        let phaseOffset: Double
    }

    private static let cols = 9
    private static let rows = 9
    private static let variants: [Variant] = [
        Variant(colorA: Color(red: 0.32, green: 0.76, blue: 1.0), colorB: Color(red: 0.78, green: 0.55, blue: 1.0), frequency: 7.0, speed: 1.8, phaseOffset: 0),
        Variant(colorA: Color(red: 0.38, green: 0.92, blue: 0.72), colorB: Color(red: 0.34, green: 0.64, blue: 1.0), frequency: 6.0, speed: 1.5, phaseOffset: .pi / 4),
        Variant(colorA: Color(red: 1.0, green: 0.56, blue: 0.72), colorB: Color(red: 0.48, green: 0.72, blue: 1.0), frequency: 8.0, speed: 2.0, phaseOffset: .pi / 2),
        Variant(colorA: Color(red: 0.72, green: 0.76, blue: 1.0), colorB: Color(red: 0.38, green: 0.94, blue: 0.88), frequency: 6.8, speed: 1.7, phaseOffset: .pi),
        Variant(colorA: Color(red: 0.54, green: 0.84, blue: 0.96), colorB: Color(red: 0.72, green: 0.52, blue: 1.0), frequency: 7.6, speed: 2.1, phaseOffset: .pi * 1.5),
    ]

    let seed: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var variant: Variant {
        let i = ((seed % Self.variants.count) + Self.variants.count) % Self.variants.count
        return Self.variants[i]
    }

    var body: some View {
        let v = variant
        let isLight = colorScheme == .light
        let bg: Color = isLight ? Color(red: 0.965, green: 0.970, blue: 0.982) : Color(red: 0.040, green: 0.046, blue: 0.066)

        Group {
            if reduceMotion {
                mosaicCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    mosaicCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func mosaicCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let cellW = size.width / CGFloat(Self.cols)
            let cellH = size.height / CGFloat(Self.rows)
            let gap = max(1.0, min(cellW, cellH) * 0.08)
            let baseOpacity = isLight ? 0.50 : 0.78

            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    let cx = (CGFloat(col) + 0.5) / CGFloat(Self.cols) - 0.5
                    let cy = (CGFloat(row) + 0.5) / CGFloat(Self.rows) - 0.5
                    let dist = sqrt(cx * cx + cy * cy)
                    let wave = sin(t * v.speed + Double(dist) * v.frequency + v.phaseOffset)
                    let norm = (wave + 1.0) * 0.5
                    let inset = gap + min(cellW, cellH) * CGFloat(0.16 * (1 - norm))
                    let rect = CGRect(
                        x: CGFloat(col) * cellW + inset,
                        y: CGFloat(row) * cellH + inset,
                        width: max(1, cellW - inset * 2),
                        height: max(1, cellH - inset * 2)
                    )
                    let color = (row + col).isMultiple(of: 2) ? v.colorA : v.colorB
                    let opacity = baseOpacity * (0.25 + norm * 0.75)

                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}
