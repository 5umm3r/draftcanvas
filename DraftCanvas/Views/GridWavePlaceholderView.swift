import SwiftUI

struct GridWavePlaceholderView: View {
    private struct RGB {
        let r: Double, g: Double, b: Double
        func color(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b).opacity(opacity) }
    }

    private struct Variant {
        let frequency: Double
        let speed: Double
        let phaseOffset: Double
        /// 波の谷(low)→山(high)で補間する2色
        let low: RGB
        let high: RGB
    }

    private static let cols = 16
    private static let rows = 16
    private static let variants: [Variant] = [
        Variant(frequency: 7.0, speed: 0.7, phaseOffset: 0,
                low: RGB(r: 0.22, g: 0.42, b: 0.62), high: RGB(r: 0.42, g: 0.80, b: 1.0)),
        Variant(frequency: 5.5, speed: 0.55, phaseOffset: .pi / 4,
                low: RGB(r: 0.20, g: 0.48, b: 0.42), high: RGB(r: 0.42, g: 0.92, b: 0.76)),
        Variant(frequency: 8.0, speed: 0.85, phaseOffset: .pi / 2,
                low: RGB(r: 0.40, g: 0.42, b: 0.58), high: RGB(r: 0.82, g: 0.82, b: 1.0)),
        Variant(frequency: 6.0, speed: 0.62, phaseOffset: .pi,
                low: RGB(r: 0.34, g: 0.28, b: 0.58), high: RGB(r: 0.66, g: 0.56, b: 1.0)),
        Variant(frequency: 7.5, speed: 0.78, phaseOffset: .pi * 1.5,
                low: RGB(r: 0.18, g: 0.46, b: 0.50), high: RGB(r: 0.40, g: 0.90, b: 0.92)),
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
            let maxRadius = min(cellW, cellH) * 0.24
            let baseOpacity = isLight ? 0.72 : 0.9

            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    let cx = (CGFloat(col) + 0.5) * cellW
                    let cy = (CGFloat(row) + 0.5) * cellH

                    let dx = cx / w - 0.5
                    let dy = cy / h - 0.5
                    let dist = sqrt(dx * dx + dy * dy)
                    let angle = atan2(dy, dx)

                    // 主: 中心同心円波 + 副: 方向うねりを加算して有機的に
                    let primary = sin(t * v.speed + dist * v.frequency + v.phaseOffset)
                    let secondary = 0.35 * sin(angle * 3 + t * v.speed * 0.6)
                    let wave = primary + secondary
                    let norm = max(0, min(1, (wave + 1.35) / 2.7))

                    let scale = 0.18 + norm * 0.82
                    let r = maxRadius * scale
                    let opacity = baseOpacity * (0.18 + norm * 0.82)

                    // 谷→山で色補間
                    let cr = v.low.r + (v.high.r - v.low.r) * norm
                    let cg = v.low.g + (v.high.g - v.low.g) * norm
                    let cb = v.low.b + (v.high.b - v.low.b) * norm
                    let dotColor = Color(red: cr, green: cg, blue: cb)

                    // 山(norm高)ほど発光グロー(他スタイルと同手法)
                    if norm > 0.55 {
                        let glowR = r * 2.6
                        let gRect = CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)
                        let shading = GraphicsContext.Shading.radialGradient(
                            Gradient(colors: [dotColor.opacity(opacity * 0.5 * (norm - 0.55) / 0.45), .clear]),
                            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR)
                        context.fill(Path(ellipseIn: gRect), with: shading)
                    }

                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(opacity)))
                }
            }
        }
    }
}
