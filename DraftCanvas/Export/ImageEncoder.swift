import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    static func jpegData(fromPNG png: Data, quality: CGFloat) throws -> Data {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ExportError.decodeFailed }

        let width = cgImage.width
        let height = cgImage.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let bm = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: bm
        ) else { throw ExportError.encodeFailed }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let composited = ctx.makeImage() else { throw ExportError.encodeFailed }

        let dest = NSMutableData()
        guard let cgDest = CGImageDestinationCreateWithData(
            dest, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw ExportError.encodeFailed }
        CGImageDestinationAddImage(cgDest, composited,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(cgDest) else { throw ExportError.encodeFailed }
        return dest as Data
    }

    static func svgWrapping(pngData: Data) throws -> Data {
        guard
            let img = NSImage(data: pngData),
            let rep = img.representations.first
        else { throw ExportError.encodeFailed }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        let base64 = pngData.base64EncodedString()
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <image href="data:image/png;base64,\(base64)" width="\(w)" height="\(h)"/>
        </svg>
        """
        guard let data = xml.data(using: .utf8) else { throw ExportError.encodeFailed }
        return data
    }
}
