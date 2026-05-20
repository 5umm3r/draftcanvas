import SwiftUI

struct AuroraPlaceholderView: View {
    private struct Blob {
        let color: Color
        let periodMult: Double
        let radiusMult: Double
        let sizeMult: Double
    }

    private struct Variant {
        let hueRotation: Double
        let speedMult: Double
        let blurMult: Double
        let phaseOffset: Double
    }

    private static let blobs: [Blob] = [
        Blob(color: Color(red: 1.00, green: 0.42, blue: 0.62), periodMult: 1.00, radiusMult: 0.32, sizeMult: 0.90), // pink
        Blob(color: Color(red: 0.77, green: 0.43, blue: 1.00), periodMult: 0.92, radiusMult: 0.38, sizeMult: 0.85), // purple
        Blob(color: Color(red: 0.29, green: 0.56, blue: 1.00), periodMult: 1.08, radiusMult: 0.28, sizeMult: 0.92), // blue
        Blob(color: Color(red: 0.36, green: 0.91, blue: 0.88), periodMult: 0.95, radiusMult: 0.35, sizeMult: 0.88), // cyan
        Blob(color: Color(red: 0.50, green: 0.91, blue: 0.36), periodMult: 1.05, radiusMult: 0.30, sizeMult: 0.86), // green
    ]
    private static let basePeriod = 4.0
    private static let variants: [Variant] = [
        Variant(hueRotation:   0, speedMult: 1.00, blurMult: 1.00, phaseOffset: 0),
        Variant(hueRotation:  72, speedMult: 0.85, blurMult: 1.07, phaseOffset: .pi / 5),
        Variant(hueRotation: 144, speedMult: 1.18, blurMult: 0.93, phaseOffset: 2 * .pi / 5),
        Variant(hueRotation: 216, speedMult: 0.92, blurMult: 1.04, phaseOffset: 3 * .pi / 5),
        Variant(hueRotation: 288, speedMult: 1.10, blurMult: 0.96, phaseOffset: 4 * .pi / 5),
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
        let blobOpacity: Double = isLight ? 0.78 : 0.9
        let blurBase: CGFloat = isLight ? 22 : 28
        let blend: BlendMode = isLight ? .multiply : .plusLighter

        Group {
            if reduceMotion {
                blobLayer(t: 0, v: v, bg: bg, blobOpacity: blobOpacity, blurBase: blurBase, blend: blend)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    blobLayer(t: t, v: v, bg: bg, blobOpacity: blobOpacity, blurBase: blurBase, blend: blend)
                }
            }
        }
        .drawingGroup()
    }

    private func blobLayer(t: Double, v: Variant, bg: Color, blobOpacity: Double, blurBase: CGFloat, blend: BlendMode) -> some View {
        GeometryReader { geo in
            let minDim = min(geo.size.width, geo.size.height)
            ZStack {
                bg
                ForEach(0..<visibleBlobCount, id: \.self) { i in
                    let blob = Self.blobs[i]
                    let phase = Double(i) * .pi * 2.0 / 5.0 + v.phaseOffset
                    let angle = t * .pi * 2.0 / (Self.basePeriod * blob.periodMult / v.speedMult) + phase
                    let blobSize = minDim * blob.sizeMult
                    RadialGradient(
                        colors: [blob.color.opacity(blobOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: blobSize / 2
                    )
                    .frame(width: blobSize, height: blobSize)
                    .offset(x: cos(angle) * minDim * blob.radiusMult,
                            y: sin(angle) * minDim * blob.radiusMult)
                    .blendMode(blend)
                }
            }
            .hueRotation(.degrees(v.hueRotation))
            .blur(radius: blurBase * v.blurMult)
        }
    }
}
