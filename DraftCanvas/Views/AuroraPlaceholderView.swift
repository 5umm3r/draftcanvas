import SwiftUI

struct AuroraPlaceholderView: View {
    private struct Blob {
        let color: Color
        let periodMult: Double
        let radiusMult: Double
        let sizeMult: Double
        /// リサージュ軌道の x/y 周波数。単純円周回より有機的なゆらぎを生む
        let freqX: Double
        let freqY: Double
    }

    private struct Variant {
        /// blob 配色の開始インデックス(色順ローテーション = 擬似 hueRotation)
        let colorOffset: Int
        let speedMult: Double
        let blurMult: CGFloat
        let phaseOffset: Double
    }

    private static let blobs: [Blob] = [
        Blob(color: Color(red: 1.00, green: 0.42, blue: 0.62), periodMult: 1.00, radiusMult: 0.30, sizeMult: 0.92, freqX: 1.0, freqY: 1.3), // pink
        Blob(color: Color(red: 0.77, green: 0.43, blue: 1.00), periodMult: 0.92, radiusMult: 0.36, sizeMult: 0.86, freqX: 1.2, freqY: 0.9), // purple
        Blob(color: Color(red: 0.29, green: 0.56, blue: 1.00), periodMult: 1.08, radiusMult: 0.26, sizeMult: 0.94, freqX: 0.8, freqY: 1.1), // blue
        Blob(color: Color(red: 0.36, green: 0.91, blue: 0.88), periodMult: 0.95, radiusMult: 0.33, sizeMult: 0.90, freqX: 1.3, freqY: 1.0), // cyan
        Blob(color: Color(red: 0.50, green: 0.91, blue: 0.36), periodMult: 1.05, radiusMult: 0.29, sizeMult: 0.88, freqX: 0.9, freqY: 1.2), // green
    ]
    /// 周回基本周期(秒)。大きいほどゆっくり
    private static let basePeriod = 7.5
    private static let variants: [Variant] = [
        Variant(colorOffset: 0, speedMult: 0.70, blurMult: 1.00, phaseOffset: 0),
        Variant(colorOffset: 1, speedMult: 0.60, blurMult: 1.07, phaseOffset: .pi / 5),
        Variant(colorOffset: 2, speedMult: 0.82, blurMult: 0.93, phaseOffset: 2 * .pi / 5),
        Variant(colorOffset: 3, speedMult: 0.64, blurMult: 1.04, phaseOffset: 3 * .pi / 5),
        Variant(colorOffset: 4, speedMult: 0.76, blurMult: 0.96, phaseOffset: 4 * .pi / 5),
    ]

    let seed: Int
    let visibleBlobCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(seed: Int = 0, visibleBlobCount: Int = 5) {
        self.seed = seed
        self.visibleBlobCount = max(1, min(visibleBlobCount, Self.blobs.count))
    }

    private var variant: Variant {
        let i = ((seed % Self.variants.count) + Self.variants.count) % Self.variants.count
        return Self.variants[i]
    }

    var body: some View {
        let v = variant
        let isLight = colorScheme == .light
        let bg: Color = isLight ? Color(red: 0.984, green: 0.984, blue: 0.992) : .black

        Group {
            if reduceMotion {
                auroraCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    auroraCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func auroraCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let minDim = min(w, h)

            // 背景はぼかさず先に塗る
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let blobOpacity: Double = isLight ? 0.78 : 0.9
            let blurBase: CGFloat = isLight ? 24 : 30
            let blend: GraphicsContext.BlendMode = isLight ? .multiply : .plusLighter

            // ブロブ群を1レイヤーにまとめ blur フィルタで柔らかく溶かす
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: blurBase * v.blurMult))
                layer.blendMode = blend

                for i in 0..<visibleBlobCount {
                    let blob = Self.blobs[(i + v.colorOffset) % Self.blobs.count]
                    let phase = Double(i) * .pi * 2.0 / 5.0 + v.phaseOffset
                    let angle = t * .pi * 2.0 / (Self.basePeriod * blob.periodMult / v.speedMult) + phase

                    // リサージュ軌道(x/y 周波数を変えゆらぎを出す)
                    let ox = cos(angle * blob.freqX) * minDim * blob.radiusMult
                    let oy = sin(angle * blob.freqY) * minDim * blob.radiusMult
                    let center = CGPoint(x: w / 2 + ox, y: h / 2 + oy)
                    let blobSize = minDim * blob.sizeMult
                    let r = blobSize / 2

                    let rect = CGRect(x: center.x - r, y: center.y - r, width: blobSize, height: blobSize)
                    let shading = GraphicsContext.Shading.radialGradient(
                        Gradient(colors: [blob.color.opacity(blobOpacity), .clear]),
                        center: center, startRadius: 0, endRadius: r)
                    layer.fill(Path(ellipseIn: rect), with: shading)
                }
            }
        }
    }
}
