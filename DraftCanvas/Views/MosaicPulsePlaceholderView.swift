import SwiftUI

struct MosaicPulsePlaceholderView: View {
    private struct Variant {
        let colorA: Color
        let colorB: Color
        let frequency: Double
        let speed: Double
        let phaseOffset: Double
    }

    private static let cols = 10
    private static let rows = 10
    private static let variants: [Variant] = [
        Variant(colorA: Color(red: 0.32, green: 0.76, blue: 1.0), colorB: Color(red: 0.78, green: 0.55, blue: 1.0), frequency: 6.5, speed: 0.62, phaseOffset: 0),
        Variant(colorA: Color(red: 0.38, green: 0.92, blue: 0.72), colorB: Color(red: 0.34, green: 0.64, blue: 1.0), frequency: 5.5, speed: 0.52, phaseOffset: .pi / 4),
        Variant(colorA: Color(red: 1.0, green: 0.56, blue: 0.72), colorB: Color(red: 0.48, green: 0.72, blue: 1.0), frequency: 7.2, speed: 0.72, phaseOffset: .pi / 2),
        Variant(colorA: Color(red: 0.72, green: 0.76, blue: 1.0), colorB: Color(red: 0.38, green: 0.94, blue: 0.88), frequency: 6.0, speed: 0.58, phaseOffset: .pi),
        Variant(colorA: Color(red: 0.54, green: 0.84, blue: 0.96), colorB: Color(red: 0.72, green: 0.52, blue: 1.0), frequency: 6.8, speed: 0.70, phaseOffset: .pi * 1.5),
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
            let w = size.width
            let h = size.height
            let minDim = min(w, h)
            let fullRect = Path(CGRect(origin: .zero, size: size))

            // 背景: ベタ塗り → 中央やや上ビネット(他スタイルと統一)
            context.fill(fullRect, with: .color(bg))
            let centerColor: Color = isLight
                ? Color(red: 0.99, green: 0.995, blue: 1.0)
                : Color(red: 0.07, green: 0.08, blue: 0.12)
            let vignette = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [centerColor, bg]),
                center: CGPoint(x: w / 2, y: h * 0.42),
                startRadius: 0, endRadius: minDim * 0.75)
            context.fill(fullRect, with: vignette)

            let cellW = w / CGFloat(Self.cols)
            let cellH = h / CGFloat(Self.rows)
            let gap = max(1.0, min(cellW, cellH) * 0.08)
            let baseOpacity = isLight ? 0.50 : 0.78
            let corner: CGFloat = 2

            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    let ndx = (CGFloat(col) + 0.5) / CGFloat(Self.cols) - 0.5
                    let ndy = (CGFloat(row) + 0.5) / CGFloat(Self.rows) - 0.5
                    let dist = sqrt(ndx * ndx + ndy * ndy)
                    let angle = atan2(ndy, ndx)

                    // 主: 同心波 + 副: 方向うねりを加算して有機的に
                    let primary = sin(t * v.speed + Double(dist) * v.frequency + v.phaseOffset)
                    let secondary = 0.3 * sin(Double(angle) * 2 + t * v.speed * 0.5)
                    let wave = primary + secondary
                    let norm = max(0, min(1, (wave + 1.3) / 2.6))

                    let inset = gap + min(cellW, cellH) * CGFloat(0.16 * (1 - norm))
                    let rect = CGRect(
                        x: CGFloat(col) * cellW + inset,
                        y: CGFloat(row) * cellH + inset,
                        width: max(1, cellW - inset * 2),
                        height: max(1, cellH - inset * 2)
                    )
                    let color = (row + col).isMultiple(of: 2) ? v.colorA : v.colorB
                    let opacity = baseOpacity * (0.22 + norm * 0.78)

                    // 点灯したタイル(norm高)の外側に一回り大きい角丸矩形を薄く敷き発光感
                    if norm > 0.6 {
                        let g = (norm - 0.6) / 0.4
                        let ext = min(cellW, cellH) * 0.10 * CGFloat(g)
                        let gRect = rect.insetBy(dx: -ext, dy: -ext)
                        context.fill(Path(roundedRect: gRect, cornerRadius: corner + ext),
                                     with: .color(color.opacity(opacity * 0.35 * g)))
                    }

                    context.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}
