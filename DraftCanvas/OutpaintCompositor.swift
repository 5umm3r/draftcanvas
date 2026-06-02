import Foundation
import CoreGraphics
import ImageIO

enum OutpaintCompositorError: Error, LocalizedError {
    case imageDecodeFailed
    case compositeFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed: return String(localized: "元画像のデコードに失敗しました。")
        case .compositeFailed: return String(localized: "アウトペイント合成に失敗しました。")
        case .encodeFailed: return String(localized: "画像エンコードに失敗しました。")
        }
    }
}

enum OutpaintCompositor {

    struct Result {
        let compositeData: Data
        let maskData: Data
        let expandedSize: CGSize
    }

    static func composite(
        originalImageData: Data,
        insets: OutpaintInsets
    ) throws -> Result {
        guard let originalCG = decodeCGImage(from: originalImageData) else {
            throw OutpaintCompositorError.imageDecodeFailed
        }

        let origW = originalCG.width
        let origH = originalCG.height
        let newW = origW + Int(insets.left.rounded()) + Int(insets.right.rounded())
        let newH = origH + Int(insets.top.rounded()) + Int(insets.bottom.rounded())
        let offsetX = Int(insets.left.rounded())
        let offsetY = Int(insets.top.rounded())

        // --- composite PNG: 元画像を配置、外周 alpha=0 ---
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: newW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw OutpaintCompositorError.compositeFailed }

        ctx.clear(CGRect(x: 0, y: 0, width: newW, height: newH))

        let destRect = CGRect(
            x: offsetX,
            y: newH - origH - offsetY,
            width: origW,
            height: origH
        )
        ctx.draw(originalCG, in: destRect)

        guard let compositeImage = ctx.makeImage() else {
            throw OutpaintCompositorError.compositeFailed
        }
        guard let compositeData = encodePNG(cgImage: compositeImage) else {
            throw OutpaintCompositorError.encodeFailed
        }

        // --- mask PNG: 外周=白(生成), 元画像領域=黒(保持) ---
        guard let maskCtx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: newW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw OutpaintCompositorError.compositeFailed }

        maskCtx.setFillColor(CGColor(gray: 1, alpha: 1))
        maskCtx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))

        maskCtx.setFillColor(CGColor(gray: 0, alpha: 1))
        maskCtx.fill(CGRect(
            x: offsetX,
            y: newH - origH - offsetY,
            width: origW,
            height: origH
        ))

        guard let maskImage = maskCtx.makeImage() else {
            throw OutpaintCompositorError.compositeFailed
        }
        guard let maskData = encodePNG(cgImage: maskImage) else {
            throw OutpaintCompositorError.encodeFailed
        }

        return Result(
            compositeData: compositeData,
            maskData: maskData,
            expandedSize: CGSize(width: newW, height: newH)
        )
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
