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
        let strokeColor: Color
        let lineWidth: CGFloat
    }

    private static let variants: [Variant] = [
        Variant(shape: .icosahedron, rotSpeedX: 0.3,  rotSpeedY: 0.2,  strokeColor: Color(red: 0.4, green: 0.85, blue: 1.0), lineWidth: 1.0),
        Variant(shape: .cube,        rotSpeedX: 0.25, rotSpeedY: 0.35, strokeColor: Color(red: 0.7, green: 0.6, blue: 1.0),  lineWidth: 1.2),
        Variant(shape: .octahedron,  rotSpeedX: 0.35, rotSpeedY: 0.25, strokeColor: Color(red: 0.4, green: 0.9, blue: 0.7),  lineWidth: 1.0),
        Variant(shape: .icosahedron, rotSpeedX: 0.2,  rotSpeedY: 0.3,  strokeColor: Color(red: 0.85, green: 0.85, blue: 0.95), lineWidth: 0.8),
        Variant(shape: .cube,        rotSpeedX: 0.3,  rotSpeedY: 0.15, strokeColor: Color(red: 0.5, green: 0.8, blue: 0.9),  lineWidth: 1.1),
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
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10000))
                    wireframeCanvas(t: t, v: v, bg: bg, isLight: isLight)
                }
            }
        }
    }

    private func wireframeCanvas(t: Float, v: Variant, bg: Color, isLight: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let vertices: [SIMD3<Float>]
            let edges: [(Int, Int)]
            switch v.shape {
            case .cube:        vertices = Self.cubeVertices; edges = Self.cubeEdges
            case .octahedron:  vertices = Self.octaVertices; edges = Self.octaEdges
            case .icosahedron: vertices = Self.icoVertices;  edges = Self.icoEdges
            }

            let rotX = rotationX(t * v.rotSpeedX)
            let rotY = rotationY(t * v.rotSpeedY)
            let rot = rotY * rotX

            let scale = Float(min(size.width, size.height)) * 0.28
            let cx = Float(size.width) / 2
            let cy = Float(size.height) / 2

            let projected = vertices.map { v -> CGPoint in
                let r = rot * v
                return CGPoint(x: CGFloat(r.x * scale + cx), y: CGFloat(-r.y * scale + cy))
            }

            let baseOpacity = isLight ? 0.6 : 0.8

            var path = Path()
            for (a, b) in edges {
                path.move(to: projected[a])
                path.addLine(to: projected[b])
            }
            context.stroke(path, with: .color(v.strokeColor.opacity(baseOpacity)), lineWidth: v.lineWidth)

            let dotRadius: CGFloat = v.lineWidth * 1.5
            for pt in projected {
                let rect = CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(v.strokeColor.opacity(baseOpacity + 0.15)))
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
}
