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
    /// 擬似z深度の前後振動速度。各粒固有位相と合わせ手前/奥を緩やかに往復させる
    private static let depthSpeed: Double = 0.22
    /// トレイル(尾)の点数と1点あたりの progress 巻き戻し量。点数を増やし尾を長く滑らかに
    private static let tailCount = 10
    private static let tailStep: Double = 0.010

    private static let variants: [Variant] = [
        Variant(colorA: Color(red: 0.34, green: 0.78, blue: 1.0), colorB: Color(red: 0.80, green: 0.52, blue: 1.0), speed: 0.075, swirl: 1.1, phaseOffset: 0),
        Variant(colorA: Color(red: 0.30, green: 0.92, blue: 0.70), colorB: Color(red: 0.35, green: 0.72, blue: 1.0), speed: 0.062, swirl: 1.3, phaseOffset: .pi / 4),
        Variant(colorA: Color(red: 1.0, green: 0.58, blue: 0.74), colorB: Color(red: 0.45, green: 0.66, blue: 1.0), speed: 0.085, swirl: 0.9, phaseOffset: .pi / 2),
        Variant(colorA: Color(red: 0.78, green: 0.86, blue: 1.0), colorB: Color(red: 0.45, green: 0.95, blue: 0.88), speed: 0.068, swirl: 1.2, phaseOffset: .pi),
        Variant(colorA: Color(red: 0.60, green: 0.55, blue: 1.0), colorB: Color(red: 0.36, green: 0.90, blue: 0.95), speed: 0.090, swirl: 1.0, phaseOffset: .pi * 1.5),
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

    /// 1粒のスナップショット。progress を起点に軌道上の座標を求める
    private struct ParticlePoint {
        let position: CGPoint
        let progress: Double
    }

    /// 螺旋軌道上の座標を progress から計算。トレイルも同じ式を巻き戻して使う
    private func orbitPoint(index: Double, progress: Double, v: Variant, center: CGPoint, minDim: CGFloat) -> CGPoint {
        let radius = minDim * CGFloat(0.10 + progress * 0.43)
        let angle = index * 2.399963 + progress * v.swirl * .pi * 2 + v.phaseOffset
        let x = center.x + CGFloat(cos(angle)) * radius
        let y = center.y + CGFloat(sin(angle)) * radius
        return CGPoint(x: x, y: y)
    }

    private func particleCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let minDim = min(w, h)
            let center = CGPoint(x: w / 2, y: h / 2)
            let fullRect = Path(CGRect(origin: .zero, size: size))

            // 背景: ベタ塗り → 中央やや上の淡いラジアルで奥行き(ビネット)。Wireframe と同手法
            context.fill(fullRect, with: .color(bg))
            let centerColor: Color = isLight
                ? Color(red: 0.99, green: 0.995, blue: 1.0)
                : Color(red: 0.07, green: 0.08, blue: 0.12)
            let vignette = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [centerColor, bg]),
                center: CGPoint(x: w / 2, y: h * 0.42),
                startRadius: 0, endRadius: minDim * 0.75)
            context.fill(fullRect, with: vignette)

            let baseOpacity = isLight ? 0.62 : 0.86

            // 各粒の現在状態を算出し depth 昇順(奥→手前)にソート
            struct Particle {
                let index: Double
                let progress: Double
                let depth: Double
                let color: Color
            }
            var particles: [Particle] = []
            particles.reserveCapacity(Self.particleCount)
            for i in 0..<Self.particleCount {
                let index = Double(i)
                let progress = (index / Double(Self.particleCount) + t * v.speed).truncatingRemainder(dividingBy: 1)
                let depth = 0.5 + 0.5 * sin(index * 2.399963 + t * Self.depthSpeed + v.phaseOffset)
                let color = i.isMultiple(of: 2) ? v.colorA : v.colorB
                particles.append(Particle(index: index, progress: progress, depth: depth, color: color))
            }
            particles.sort { $0.depth < $1.depth }

            for p in particles {
                let pos = orbitPoint(index: p.index, progress: p.progress, v: v, center: center, minDim: minDim)
                // 手前ほど大きく明るい。progress で外周フェードも併用
                let fade = (1 - p.progress)
                let dotSize = minDim * CGFloat(0.010 + (0.018 * fade) * (0.5 + 0.5 * p.depth))
                let opacity = baseOpacity * fade * (0.35 + 0.65 * p.depth)

                // トレイル(尾): progress を巻き戻した位置に減衰する点列
                for k in 1...Self.tailCount {
                    let kf = Double(k)
                    var pastProgress = p.progress - kf * Self.tailStep
                    if pastProgress < 0 { pastProgress += 1 }
                    let tailPos = orbitPoint(index: p.index, progress: pastProgress, v: v, center: center, minDim: minDim)
                    let decay = 1 - kf / Double(Self.tailCount + 1)
                    let tSize = dotSize * CGFloat(decay) * 0.7
                    let tOpacity = opacity * decay * 0.4
                    let rect = CGRect(x: tailPos.x - tSize / 2, y: tailPos.y - tSize / 2, width: tSize, height: tSize)
                    context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(tOpacity)))
                }

                // 発光グロー: ラジアルグラデーション(color→clear)。Wireframe 頂点と同手法
                let glowR = dotSize * 2.5
                let glowRect = CGRect(x: pos.x - glowR, y: pos.y - glowR, width: glowR * 2, height: glowR * 2)
                let glowShading = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [p.color.opacity(opacity * 0.5), .clear]),
                    center: pos, startRadius: 0, endRadius: glowR)
                context.fill(Path(ellipseIn: glowRect), with: glowShading)

                // 芯ドット
                let rect = CGRect(x: pos.x - dotSize / 2, y: pos.y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(opacity)))
            }
        }
    }
}
