import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageResizer {
    static func resize(pngData: Data, targetWidth: Int, targetHeight: Int) throws -> Data {
        guard
            let src = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ExportError.decodeFailed }

        let cs = cg.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bm = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: bm
        ) else { throw ExportError.resizeFailed }

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let out = ctx.makeImage() else { throw ExportError.resizeFailed }

        let dest = NSMutableData()
        guard let cgDest = CGImageDestinationCreateWithData(
            dest, UTType.png.identifier as CFString, 1, nil
        ) else { throw ExportError.encodeFailed }
        CGImageDestinationAddImage(cgDest, out, nil)
        guard CGImageDestinationFinalize(cgDest) else { throw ExportError.encodeFailed }
        return dest as Data
    }
}
