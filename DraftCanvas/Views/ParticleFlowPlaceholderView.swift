import SwiftUI

struct ParticleFlowPlaceholderView: View {
    private struct Variant {
        let colorA: Color
        let colorB: Color
        let speed: Double
        let swirl: Double
        let phaseOffset: Double
    }

    private static let particleCount = 48
    private static let variants: [Variant] = [
        Variant(colorA: Color(red: 0.34, green: 0.78, blue: 1.0), colorB: Color(red: 0.80, green: 0.52, blue: 1.0), speed: 0.18, swirl: 1.8, phaseOffset: 0),
        Variant(colorA: Color(red: 0.30, green: 0.92, blue: 0.70), colorB: Color(red: 0.35, green: 0.72, blue: 1.0), speed: 0.15, swirl: 2.2, phaseOffset: .pi / 4),
        Variant(colorA: Color(red: 1.0, green: 0.58, blue: 0.74), colorB: Color(red: 0.45, green: 0.66, blue: 1.0), speed: 0.20, swirl: 1.5, phaseOffset: .pi / 2),
        Variant(colorA: Color(red: 0.78, green: 0.86, blue: 1.0), colorB: Color(red: 0.45, green: 0.95, blue: 0.88), speed: 0.16, swirl: 2.0, phaseOffset: .pi),
        Variant(colorA: Color(red: 0.60, green: 0.55, blue: 1.0), colorB: Color(red: 0.36, green: 0.90, blue: 0.95), speed: 0.22, swirl: 1.7, phaseOffset: .pi * 1.5),
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
        let bg: Color = isLight ? Color(red: 0.965, green: 0.972, blue: 0.985) : Color(red: 0.035, green: 0.045, blue: 0.070)

        Group {
            if reduceMotion {
                particleCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    particleCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func particleCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let minDim = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let baseOpacity = isLight ? 0.62 : 0.86

            for i in 0..<Self.particleCount {
                let index = Double(i)
                let progress = (index / Double(Self.particleCount) + t * v.speed).truncatingRemainder(dividingBy: 1)
                let radius = minDim * (0.10 + progress * 0.43)
                let angle = index * 2.399963 + progress * v.swirl * .pi * 2 + v.phaseOffset
                let x = center.x + CGFloat(cos(angle)) * radius
                let y = center.y + CGFloat(sin(angle)) * radius
                let dotSize = minDim * CGFloat(0.012 + (1 - progress) * 0.025)
                let opacity = baseOpacity * (1 - progress) * 0.95
                let color = i.isMultiple(of: 2) ? v.colorA : v.colorB
                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)

                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}
