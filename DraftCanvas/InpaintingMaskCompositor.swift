import Foundation
import CoreGraphics
import ImageIO

struct MaskStroke: Equatable {
    let points: [CGPoint]
    let radius: CGFloat
    let isEraser: Bool
}

enum InpaintingCompositorError: Error, LocalizedError {
    case imageDecodeFailed
    case maskDecodeFailed
    case maskRenderFailed
    case compositeFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed: return "元画像のデコードに失敗しました。"
        case .maskDecodeFailed: return "マスク画像のデコードに失敗しました。"
        case .maskRenderFailed: return "マスク画像の生成に失敗しました。"
        case .compositeFailed: return "マスク合成に失敗しました。"
        case .encodeFailed: return "画像エンコードに失敗しました。"
        }
    }
}

enum InpaintingMaskCompositor {

    // MARK: - Mask rendering

    static func renderMask(from strokes: [MaskStroke], canvasSize: CGSize) -> Data? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for stroke in strokes {
            let color: CGColor = stroke.isEraser
                ? CGColor(gray: 0, alpha: 1)
                : CGColor(gray: 1, alpha: 1)
            ctx.setFillColor(color)
            drawStroke(stroke, in: ctx, canvasHeight: CGFloat(height))
        }

        guard let image = ctx.makeImage() else { return nil }
        return encodePNG(cgImage: image)
    }

    private static func drawStroke(_ stroke: MaskStroke, in ctx: CGContext, canvasHeight: CGFloat) {
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

    // MARK: - Composite

    static func composite(originalImageData: Data, maskData: Data) throws -> Data {
        guard let originalCG = decodeCGImage(from: originalImageData) else {
            throw InpaintingCompositorError.imageDecodeFailed
        }
        guard let maskCG = decodeCGImage(from: maskData) else {
            throw InpaintingCompositorError.maskDecodeFailed
        }

        let width = originalCG.width
        let height = originalCG.height

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw InpaintingCompositorError.compositeFailed }

        ctx.draw(originalCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = ctx.data else {
            throw InpaintingCompositorError.compositeFailed
        }

        guard let maskCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw InpaintingCompositorError.compositeFailed }

        maskCtx.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let maskPixelData = maskCtx.data else {
            throw InpaintingCompositorError.compositeFailed
        }

        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let maskPixels = maskPixelData.bindMemory(to: UInt8.self, capacity: width * height)

        for i in 0 ..< (width * height) {
            if maskPixels[i] > 128 {
                pixels[i * 4 + 0] = 0
                pixels[i * 4 + 1] = 0
                pixels[i * 4 + 2] = 0
                pixels[i * 4 + 3] = 0
            }
        }

        guard let resultImage = ctx.makeImage() else {
            throw InpaintingCompositorError.compositeFailed
        }
        guard let encoded = encodePNG(cgImage: resultImage) else {
            throw InpaintingCompositorError.encodeFailed
        }
        return encoded
    }

    // MARK: - Helpers

    private static func decodeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func encodePNG(cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
