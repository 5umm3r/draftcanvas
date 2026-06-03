import SwiftUI

struct ScanlineSweepPlaceholderView: View {
    private struct Variant {
        let accent: Color
        let secondary: Color
        let speed: Double
        let phaseOffset: Double
    }

    /// ドット格子の列数・行数
    private static let cols = 18
    private static let rows = 14
    /// 走査線通過後(後方)の残光減衰長と、通過前(前方)の先行光長。0..1正規化座標基準
    private static let trailLen: Double = 0.34
    private static let leadLen: Double = 0.06

    private static let variants: [Variant] = [
        Variant(accent: Color(red: 0.34, green: 0.78, blue: 1.0), secondary: Color(red: 0.80, green: 0.55, blue: 1.0), speed: 0.11, phaseOffset: 0),
        Variant(accent: Color(red: 0.42, green: 0.95, blue: 0.74), secondary: Color(red: 0.35, green: 0.65, blue: 1.0), speed: 0.095, phaseOffset: 0.2),
        Variant(accent: Color(red: 1.0, green: 0.62, blue: 0.76), secondary: Color(red: 0.50, green: 0.70, blue: 1.0), speed: 0.125, phaseOffset: 0.4),
        Variant(accent: Color(red: 0.72, green: 0.72, blue: 1.0), secondary: Color(red: 0.36, green: 0.94, blue: 0.90), speed: 0.10, phaseOffset: 0.6),
        Variant(accent: Color(red: 0.50, green: 0.86, blue: 0.96), secondary: Color(red: 0.72, green: 0.52, blue: 1.0), speed: 0.13, phaseOffset: 0.8),
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
                scanlineCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    scanlineCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    /// 後方に長く尾を引く非対称な減衰。dist>0=未通過(前方), dist<=0=通過済(後方残光)
    private func sweepGlow(dist: Double) -> Double {
        let range = dist <= 0 ? Self.trailLen : Self.leadLen
        return exp(-abs(dist) / range)
    }

    private func scanlineCanvas(t: Double, v: Variant, bg: Color, isLight: Bool) -> some View {
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

            // サイクル: 前半=水平走査(横線が上→下), 後半=垂直走査(縦線が左→右)
            let cycle = (t * v.speed + v.phaseOffset).truncatingRemainder(dividingBy: 1)
            let horizontalActive = cycle < 0.5
            // 走査位置(0..1)。バーが画面外から入り外へ抜けるよう -lead..1+trail 余白を持たせる
            let sweep: Double = horizontalActive ? (cycle * 2) : ((cycle - 0.5) * 2)
            let sweepColor = horizontalActive ? v.accent : v.secondary
            let crossColor = horizontalActive ? v.secondary : v.accent

            let baseDot = isLight ? 0.10 : 0.16
            let peakDot = isLight ? 0.55 : 0.82
            let dotBaseR = minDim * 0.006

            // ドット格子: 走査線との距離で点灯。手前ほどグロー
            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    let nx = (Double(col) + 0.5) / Double(Self.cols)
                    let ny = (Double(row) + 0.5) / Double(Self.rows)
                    let px = CGFloat(nx) * w
                    let py = CGFloat(ny) * h

                    // アクティブ軸の走査線からの符号付き距離(進行方向が正=前方)
                    let along = horizontalActive ? ny : nx
                    let dist = along - sweep
                    let glow = sweepGlow(dist: dist)

                    let intensity = baseDot + (peakDot - baseDot) * glow
                    let r = dotBaseR * (1 + 1.6 * glow)

                    // ピーク付近のみソフトな発光を敷く
                    if glow > 0.08 {
                        let glowR = r * 3.0
                        let gRect = CGRect(x: px - glowR, y: py - glowR, width: glowR * 2, height: glowR * 2)
                        let shading = GraphicsContext.Shading.radialGradient(
                            Gradient(colors: [sweepColor.opacity(intensity * 0.6), .clear]),
                            center: CGPoint(x: px, y: py), startRadius: 0, endRadius: glowR)
                        context.fill(Path(ellipseIn: gRect), with: shading)
                    }

                    let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(sweepColor.opacity(intensity)))
                }
            }

            // 走査線本体: アクティブ軸に沿った発光ライン(太→細のalpha重ね描きでソフト発光)
            let lineGlow = isLight ? 0.30 : 0.50
            let sweepPos = CGFloat(sweep)
            var linePath = Path()
            if horizontalActive {
                let y = sweepPos * h
                linePath.move(to: CGPoint(x: 0, y: y))
                linePath.addLine(to: CGPoint(x: w, y: y))
            } else {
                let x = sweepPos * w
                linePath.move(to: CGPoint(x: x, y: 0))
                linePath.addLine(to: CGPoint(x: x, y: h))
            }
            // 走査線が画面内のときのみ描画
            if sweep >= 0 && sweep <= 1 {
                for (mult, op) in [(6.0 as CGFloat, lineGlow * 0.12), (2.5 as CGFloat, lineGlow * 0.22), (1.0 as CGFloat, lineGlow * 0.9)] {
                    context.stroke(linePath, with: .color(sweepColor.opacity(op)),
                                   style: StrokeStyle(lineWidth: mult, lineCap: .round))
                }
            }

            // 直交方向の淡い基準グリッド線(常時, 控えめ)。走査と垂直な軸を薄く示す
            let gridOp = isLight ? 0.06 : 0.10
            var gridPath = Path()
            if horizontalActive {
                for col in 0..<Self.cols {
                    let x = (CGFloat(col) + 0.5) / CGFloat(Self.cols) * w
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: h))
                }
            } else {
                for row in 0..<Self.rows {
                    let y = (CGFloat(row) + 0.5) / CGFloat(Self.rows) * h
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: w, y: y))
                }
            }
            context.stroke(gridPath, with: .color(crossColor.opacity(gridOp)),
                           style: StrokeStyle(lineWidth: 0.6))
        }
    }
}
