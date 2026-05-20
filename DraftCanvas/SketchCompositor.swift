import Foundation
import CoreGraphics
import ImageIO

enum SketchCompositor {

    // MARK: - Render PNG

    static func renderPNG(from strokes: [SketchStroke], canvasSize: CGSize) -> Data? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 白背景
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for stroke in strokes {
            let color = stroke.isEraser
                ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                : stroke.color.cgColor
            ctx.setFillColor(color)
            drawStroke(stroke, in: ctx, canvasHeight: CGFloat(height))
        }

        guard let image = ctx.makeImage() else { return nil }
        return encodePNG(cgImage: image)
    }

    // MARK: - Stroke drawing

    private static func drawStroke(_ stroke: SketchStroke, in ctx: CGContext, canvasHeight: CGFloat) {
        guard !stroke.points.isEmpty else { return }
        let r = max(1, stroke.radius)

        func flipY(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: canvasHeight - p.y)
        }

        if stroke.points.count == 1 {
            let p = flipY(stroke.points[0])
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            return
        }

        for i in 1 ..< stroke.points.count {
            let p0 = flipY(stroke.points[i - 1])
            let p1 = flipY(stroke.points[i])
            let dist = hypot(p1.x - p0.x, p1.y - p0.y)
            let steps = max(1, Int(dist / (r * 0.5)))
            for s in 0 ... steps {
                let t = CGFloat(s) / CGFloat(steps)
                let x = p0.x + (p1.x - p0.x) * t
                let y = p0.y + (p1.y - p0.y) * t
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: - Helpers

    private static func encodePNG(cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
