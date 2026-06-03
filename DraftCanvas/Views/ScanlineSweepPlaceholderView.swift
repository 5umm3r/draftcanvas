import SwiftUI

struct ScanlineSweepPlaceholderView: View {
    private struct Variant {
        let accent: Color
        let secondary: Color
        let speed: Double
        let phaseOffset: Double
    }

    private static let variants: [Variant] = [
        Variant(accent: Color(red: 0.34, green: 0.78, blue: 1.0), secondary: Color(red: 0.80, green: 0.55, blue: 1.0), speed: 0.34, phaseOffset: 0),
        Variant(accent: Color(red: 0.42, green: 0.95, blue: 0.74), secondary: Color(red: 0.35, green: 0.65, blue: 1.0), speed: 0.30, phaseOffset: 0.2),
        Variant(accent: Color(red: 1.0, green: 0.62, blue: 0.76), secondary: Color(red: 0.50, green: 0.70, blue: 1.0), speed: 0.38, phaseOffset: 0.4),
        Variant(accent: Color(red: 0.72, green: 0.72, blue: 1.0), secondary: Color(red: 0.36, green: 0.94, blue: 0.90), speed: 0.32, phaseOffset: 0.6),
        Variant(accent: Color(red: 0.50, green: 0.86, blue: 0.96), secondary: Color(red: 0.72, green: 0.52, blue: 1.0), speed: 0.40, phaseOffset: 0.8),
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
        let bg: Color = isLight ? Color(red: 0.965, green: 0.970, blue: 0.980) : Color(red: 0.040, green: 0.046, blue: 0.062)

        Group {
            if reduceMotion {
                scanlineLayer(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    scanlineLayer(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
        .drawingGroup()
    }

    private func scanlineLayer(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        GeometryReader { geo in
            let cycle = (t * v.speed + v.phaseOffset).truncatingRemainder(dividingBy: 1)
            let horizontalPhase = cycle < 0.5 ? cycle * 2 : 0
            let verticalPhase = cycle >= 0.5 ? (cycle - 0.5) * 2 : 0
            let horizontalActive = cycle < 0.5
            let lineOpacity = isLight ? 0.18 : 0.32
            let majorLineOpacity = isLight ? 0.30 : 0.48
            let glowOpacity = isLight ? 0.34 : 0.58

            ZStack {
                bg
                LinearGradient(
                    colors: [
                        v.secondary.opacity(0.16),
                        Color.clear,
                        v.accent.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(0..<24, id: \.self) { i in
                    let isMajor = i.isMultiple(of: 4)
                    Rectangle()
                        .fill(v.accent.opacity(isMajor ? majorLineOpacity : lineOpacity))
                        .frame(height: isMajor ? 1.2 : 0.7)
                        .offset(y: CGFloat(i) * geo.size.height / 24.0 - geo.size.height / 2.0)
                }

                ForEach(0..<24, id: \.self) { i in
                    let isMajor = i.isMultiple(of: 4)
                    Rectangle()
                        .fill(v.secondary.opacity(isMajor ? majorLineOpacity * 0.85 : lineOpacity * 0.75))
                        .frame(width: isMajor ? 1.2 : 0.7)
                        .offset(x: CGFloat(i) * geo.size.width / 24.0 - geo.size.width / 2.0)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, v.accent.opacity(glowOpacity), v.secondary.opacity(glowOpacity * 0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width, height: max(24, geo.size.height * 0.18))
                    .blur(radius: 5)
                    .offset(y: CGFloat(horizontalPhase) * (geo.size.height * 1.35) - geo.size.height * 0.68)
                    .opacity(horizontalActive ? 1 : 0)
                    .blendMode(isLight ? .multiply : .plusLighter)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, v.accent.opacity(glowOpacity), v.secondary.opacity(glowOpacity * 0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(24, geo.size.width * 0.18), height: geo.size.height)
                    .blur(radius: 5)
                    .offset(x: CGFloat(verticalPhase) * (geo.size.width * 1.35) - geo.size.width * 0.68)
                    .opacity(horizontalActive ? 0 : 1)
                    .blendMode(isLight ? .multiply : .plusLighter)
            }
        }
    }
}
