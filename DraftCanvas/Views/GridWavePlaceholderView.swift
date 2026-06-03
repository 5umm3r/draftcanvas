import SwiftUI

struct GridWavePlaceholderView: View {
    private struct Variant {
        let frequency: Double
        let speed: Double
        let dotColor: Color
        let phaseOffset: Double
    }

    private static let cols = 14
    private static let rows = 14
    private static let variants: [Variant] = [
        Variant(frequency: 8.0,  speed: 1.8, dotColor: Color(red: 0.3, green: 0.7, blue: 1.0),  phaseOffset: 0),
        Variant(frequency: 6.0,  speed: 1.4, dotColor: Color(red: 0.4, green: 0.9, blue: 0.75), phaseOffset: .pi / 4),
        Variant(frequency: 10.0, speed: 2.2, dotColor: Color(red: 0.8, green: 0.8, blue: 0.95), phaseOffset: .pi / 2),
        Variant(frequency: 7.0,  speed: 1.6, dotColor: Color(red: 0.6, green: 0.5, blue: 1.0),  phaseOffset: .pi),
        Variant(frequency: 9.0,  speed: 2.0, dotColor: Color(red: 0.3, green: 0.85, blue: 0.85), phaseOffset: .pi * 1.5),
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
        let bg: Color = isLight ? Color(red: 0.96, green: 0.97, blue: 0.98) : Color(red: 0.05, green: 0.06, blue: 0.09)

        Group {
            if reduceMotion {
                gridCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    gridCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func gridCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let cellW = size.width / CGFloat(Self.cols)
            let cellH = size.height / CGFloat(Self.rows)
            let maxRadius = min(cellW, cellH) * 0.22
            let baseOpacity = isLight ? 0.75 : 0.9

            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    let cx = (CGFloat(col) + 0.5) * cellW
                    let cy = (CGFloat(row) + 0.5) * cellH

                    let dx = cx / size.width - 0.5
                    let dy = cy / size.height - 0.5
                    let dist = sqrt(dx * dx + dy * dy)

                    let wave = sin(t * v.speed + dist * v.frequency + v.phaseOffset)
                    let norm = (wave + 1.0) * 0.5
                    let scale = 0.15 + norm * 0.85
                    let r = maxRadius * scale
                    let opacity = baseOpacity * (0.2 + norm * 0.8)

                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(v.dotColor.opacity(opacity)))
                }
            }
        }
    }
}
