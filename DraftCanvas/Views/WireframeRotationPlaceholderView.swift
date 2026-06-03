import SwiftUI
import simd

struct WireframeRotationPlaceholderView: View {
    private enum Shape {
        case cube
        case octahedron
        case icosahedron
    }

    private struct Variant {
        let shape: Shape
        let rotSpeedX: Float
        let rotSpeedY: Float
        let ampX: Float
        let ampY: Float
        let freqX: Float
        let freqY: Float
        let r: Double
        let g: Double
        let b: Double
        let lineWidth: CGFloat

        /// light時は彩度の低い線色が明るい背景に埋もれるため暗側へ補正する
        func strokeColor(isLight: Bool) -> Color {
            let k = isLight ? 0.72 : 1.0
            return Color(red: r * k, green: g * k, blue: b * k)
        }
    }

    private static let variants: [Variant] = [
        Variant(shape: .icosahedron, rotSpeedX: 0.22, rotSpeedY: 0.16, ampX: 0.18, ampY: 0.14, freqX: 0.11, freqY: 0.13, r: 0.55, g: 0.68, b: 0.78, lineWidth: 1.0), // スモーキーブルー
        Variant(shape: .cube,        rotSpeedX: 0.18, rotSpeedY: 0.26, ampX: 0.20, ampY: 0.16, freqX: 0.09, freqY: 0.12, r: 0.62, g: 0.66, b: 0.70, lineWidth: 1.2), // グラファイト
        Variant(shape: .octahedron,  rotSpeedX: 0.26, rotSpeedY: 0.18, ampX: 0.15, ampY: 0.20, freqX: 0.13, freqY: 0.10, r: 0.56, g: 0.70, b: 0.64, lineWidth: 1.0), // セージ
        Variant(shape: .icosahedron, rotSpeedX: 0.15, rotSpeedY: 0.22, ampX: 0.22, ampY: 0.18, freqX: 0.08, freqY: 0.14, r: 0.74, g: 0.72, b: 0.68, lineWidth: 0.9), // ウォームグレー
        Variant(shape: .cube,        rotSpeedX: 0.22, rotSpeedY: 0.13, ampX: 0.16, ampY: 0.22, freqX: 0.12, freqY: 0.09, r: 0.50, g: 0.60, b: 0.66, lineWidth: 1.1), // スレートブルー
    ]

    private static let cubeVertices: [SIMD3<Float>] = [
        SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
        SIMD3(-1, -1,  1), SIMD3(1, -1,  1), SIMD3(1, 1,  1), SIMD3(-1, 1,  1),
    ]
    private static let cubeEdges: [(Int, Int)] = [
        (0,1),(1,2),(2,3),(3,0), (4,5),(5,6),(6,7),(7,4), (0,4),(1,5),(2,6),(3,7),
    ]

    private static let octaVertices: [SIMD3<Float>] = [
        SIMD3(1,0,0), SIMD3(-1,0,0), SIMD3(0,1,0), SIMD3(0,-1,0), SIMD3(0,0,1), SIMD3(0,0,-1),
    ]
    private static let octaEdges: [(Int, Int)] = [
        (0,2),(0,3),(0,4),(0,5), (1,2),(1,3),(1,4),(1,5), (2,4),(2,5),(3,4),(3,5),
    ]

    private static let phi: Float = (1.0 + sqrt(5.0)) / 2.0
    private static let icoVertices: [SIMD3<Float>] = {
        let p = phi
        return [
            SIMD3(-1, p, 0), SIMD3(1, p, 0), SIMD3(-1, -p, 0), SIMD3(1, -p, 0),
            SIMD3(0, -1, p), SIMD3(0, 1, p), SIMD3(0, -1, -p), SIMD3(0, 1, -p),
            SIMD3(p, 0, -1), SIMD3(p, 0, 1), SIMD3(-p, 0, -1), SIMD3(-p, 0, 1),
        ]
    }()
    private static let icoEdges: [(Int, Int)] = [
        (0,1),(0,5),(0,7),(0,10),(0,11), (1,5),(1,7),(1,8),(1,9),
        (2,3),(2,4),(2,6),(2,10),(2,11), (3,4),(3,6),(3,8),(3,9),
        (4,5),(4,9),(4,11), (5,9),(5,11), (6,7),(6,8),(6,10), (7,8),(7,10),
        (8,9), (10,11),
    ]

    /// 回転後 z の取りうる最大絶対値（= 頂点ノルムの最大）。深度正規化を毎フレーム固定レンジで行い明滅を防ぐ。
    private static func zMax(for shape: Shape) -> Float {
        switch shape {
        case .cube:        return 1.7320508   // sqrt(3)
        case .octahedron:  return 1.0
        case .icosahedron: return 1.9021130   // sqrt(2 + phi)
        }
    }

    private static let frameInterval: Double = 1.0 / 60.0

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
                wireframeCanvas(t: 0, v: v, bg: bg, isLight: isLight)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                TimelineView(.animation(minimumInterval: Self.frameInterval)) { context in
                    let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10000))
                    wireframeCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func wireframeCanvas(t: Float, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let minDim = min(w, h)
            let fullRect = Path(CGRect(origin: .zero, size: size))

            // 背景: ベタ塗り → 中央やや上の淡いラジアルで奥行き(ビネット)
            context.fill(fullRect, with: .color(bg))
            let centerColor: Color = isLight
                ? Color(red: 0.99, green: 0.995, blue: 1.0)
                : Color(red: 0.07, green: 0.08, blue: 0.12)
            let vignette = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [centerColor, bg]),
                center: CGPoint(x: w / 2, y: h * 0.42),
                startRadius: 0, endRadius: minDim * 0.75)
            context.fill(fullRect, with: vignette)

            // 形状
            let vertices: [SIMD3<Float>]
            let edges: [(Int, Int)]
            switch v.shape {
            case .cube:        vertices = Self.cubeVertices; edges = Self.cubeEdges
            case .octahedron:  vertices = Self.octaVertices; edges = Self.octaEdges
            case .icosahedron: vertices = Self.icoVertices;  edges = Self.icoEdges
            }
            let zMax = Self.zMax(for: v.shape)

            // 有機的回転: 緩やかな線形回転 + 低周波の揺らぎ + わずかな歳差
            let phaseX: Float = 0.0
            let phaseY: Float = 1.7
            let angleX = t * v.rotSpeedX + v.ampX * sin(v.freqX * t + phaseX)
            let angleY = t * v.rotSpeedY + v.ampY * sin(v.freqY * t + phaseY)
            let angleZ = 0.15 * sin(0.05 * t)
            let rot = rotationZ(angleZ) * rotationY(angleY) * rotationX(angleX)

            let breath = 1 + 0.07 * sin(0.5 * t)   // ゆっくりした呼吸(周期≈12.6s)。t=0で1.0 → reduceMotion静止が安定
            let scale = Float(minDim) * 0.24 * breath
            let cx = Float(w) / 2
            let cy = Float(h) / 2
            let d: Float = 4.5   // カメラ距離。モデル半径(最大≈1.9)より十分大きく d - r.z は最小でも 2.6 > 0

            // 透視投影 + 固定レンジ深度
            let pvs: [(pt: CGPoint, depth: CGFloat)] = vertices.map { vert in
                let r = rot * vert
                let persp = d / (d - r.z)
                let px = CGFloat(r.x * scale * persp + cx)
                let py = CGFloat(-r.y * scale * persp + cy)
                let depth = CGFloat((r.z + zMax) / (2 * zMax)) // 0=最奥, 1=最手前
                return (CGPoint(x: px, y: py), depth)
            }

            let baseOpacity = isLight ? 0.6 : 0.8
            let stroke = v.strokeColor(isLight: isLight)

            // グロー: 全エッジを1本のPathにまとめ、太→細のalpha重ね描きでソフトな発光を近似(blur不使用)
            var glowPath = Path()
            for (a, b) in edges {
                glowPath.move(to: pvs[a].pt)
                glowPath.addLine(to: pvs[b].pt)
            }
            for (mult, op) in [(3.0 as CGFloat, baseOpacity * 0.10), (1.8 as CGFloat, baseOpacity * 0.18)] {
                context.stroke(glowPath, with: .color(stroke.opacity(op)),
                               style: StrokeStyle(lineWidth: v.lineWidth * mult, lineCap: .round, lineJoin: .round))
            }

            // 芯: エッジ単位で深度シェーディング。奥→手前の順に描き手前を上へ重ねる
            let sortedEdges = edges.sorted { e1, e2 in
                ((pvs[e1.0].depth + pvs[e1.1].depth)) < ((pvs[e2.0].depth + pvs[e2.1].depth))
            }
            for (a, b) in sortedEdges {
                let dEdge = (pvs[a].depth + pvs[b].depth) * 0.5
                let op = baseOpacity * (0.35 + 0.65 * Double(dEdge))
                let lw = v.lineWidth * (0.7 + 0.6 * dEdge)
                var p = Path()
                p.move(to: pvs[a].pt)
                p.addLine(to: pvs[b].pt)
                context.stroke(p, with: .color(stroke.opacity(op)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // 頂点: 手前ほど大きく光る。発光(ラジアル) → 芯ドット の順
            for pv in pvs {
                let depth = pv.depth
                let dotRadius = v.lineWidth * (1.1 + 0.9 * depth)
                let glowR = dotRadius * 2.5
                let glowRect = CGRect(x: pv.pt.x - glowR, y: pv.pt.y - glowR, width: glowR * 2, height: glowR * 2)
                let glowShading = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [stroke.opacity(0.4 * Double(depth)), .clear]),
                    center: pv.pt, startRadius: 0, endRadius: glowR)
                context.fill(Path(ellipseIn: glowRect), with: glowShading)

                let dotOp = (baseOpacity + 0.15) * (0.3 + 0.7 * Double(depth))
                let rect = CGRect(x: pv.pt.x - dotRadius, y: pv.pt.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(stroke.opacity(dotOp)))
            }
        }
    }

    private func rotationX(_ angle: Float) -> simd_float3x3 {
        let c = cos(angle), s = sin(angle)
        return simd_float3x3(
            SIMD3(1, 0, 0),
            SIMD3(0, c, -s),
            SIMD3(0, s, c)
        )
    }

    private func rotationY(_ angle: Float) -> simd_float3x3 {
        let c = cos(angle), s = sin(angle)
        return simd_float3x3(
            SIMD3(c, 0, s),
            SIMD3(0, 1, 0),
            SIMD3(-s, 0, c)
        )
    }

    private func rotationZ(_ angle: Float) -> simd_float3x3 {
        let c = cos(angle), s = sin(angle)
        return simd_float3x3(
            SIMD3(c, -s, 0),
            SIMD3(s, c, 0),
            SIMD3(0, 0, 1)
        )
    }
}
