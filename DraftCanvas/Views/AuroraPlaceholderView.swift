import SwiftUI

struct AuroraPlaceholderView: View {
    private struct Blob {
        let color: Color
        let periodMult: Double
        let radiusMult: Double
        let sizeMult: Double
    }

    private static let blobs: [Blob] = [
        Blob(color: Color(red: 1.00, green: 0.42, blue: 0.62), periodMult: 1.00, radiusMult: 0.32, sizeMult: 0.90), // pink
        Blob(color: Color(red: 0.77, green: 0.43, blue: 1.00), periodMult: 0.92, radiusMult: 0.38, sizeMult: 0.85), // purple
        Blob(color: Color(red: 0.29, green: 0.56, blue: 1.00), periodMult: 1.08, radiusMult: 0.28, sizeMult: 0.92), // blue
        Blob(color: Color(red: 0.36, green: 0.91, blue: 0.88), periodMult: 0.95, radiusMult: 0.35, sizeMult: 0.88), // cyan
        Blob(color: Color(red: 0.50, green: 0.91, blue: 0.36), periodMult: 1.05, radiusMult: 0.30, sizeMult: 0.86), // green
    ]
    private static let basePeriod = 4.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let minDim = min(geo.size.width, geo.size.height)
                ZStack {
                    Color.black
                    ForEach(0..<5, id: \.self) { i in
                        let blob = Self.blobs[i]
                        let phase = Double(i) * .pi * 2.0 / 5.0
                        let angle = t * .pi * 2.0 / (Self.basePeriod * blob.periodMult) + phase
                        let blobSize = minDim * blob.sizeMult
                        RadialGradient(
                            colors: [blob.color.opacity(0.9), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: blobSize / 2
                        )
                        .frame(width: blobSize, height: blobSize)
                        .offset(x: cos(angle) * minDim * blob.radiusMult,
                                y: sin(angle) * minDim * blob.radiusMult)
                        .blendMode(.plusLighter)
                    }
                }
                .blur(radius: 28)
            }
        }
        .drawingGroup()
    }
}
