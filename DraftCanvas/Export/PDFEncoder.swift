import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PDFEncoder {
    static func encode(
        pngData: Data,
        dpi: ExportDPI,
        compression: PDFImageCompression
    ) throws -> Data {
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ExportError.decodeFailed }

        let converted = cgImage

        let pxW = converted.width
        let pxH = converted.height
        guard pxW > 0, pxH > 0 else { throw ExportError.encodeFailed }

        // PDF points = px / dpi * 72
        let ptW = CGFloat(pxW) / CGFloat(dpi.rawValue) * 72.0
        let ptH = CGFloat(pxH) / CGFloat(dpi.rawValue) * 72.0
        var mediaBox = CGRect(x: 0, y: 0, width: ptW, height: ptH)

        let imageData = try imageData(from: converted, compression: compression)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.encodeFailed }

        ctx.beginPDFPage(nil)
        ctx.draw(converted, in: mediaBox)
        ctx.endPDFPage()
        ctx.closePDF()

        // Re-encode via ImageIO when JPEG compression requested (smaller file)
        // For lossless, the draw-based approach above is sufficient.
        // When JPEG compression is requested, rebuild the PDF with embedded JPEG stream.
        if compression != .lossless {
            return try buildPDFWithEmbeddedImage(imageData: imageData, mediaBox: mediaBox)
        }

        return pdfData as Data
    }

    // MARK: - Private

    private static func imageData(from image: CGImage, compression: PDFImageCompression) throws -> Data {
        switch compression {
        case .lossless:
            let dest = NSMutableData()
            guard let cgDest = CGImageDestinationCreateWithData(
                dest, UTType.png.identifier as CFString, 1, nil
            ) else { throw ExportError.encodeFailed }
            CGImageDestinationAddImage(cgDest, image, nil)
            guard CGImageDestinationFinalize(cgDest) else { throw ExportError.encodeFailed }
            return dest as Data

        case .jpegHigh:
            return try encodeJPEG(image: image, quality: 0.9)
        case .jpegMedium:
            return try encodeJPEG(image: image, quality: 0.7)
        }
    }

    private static func encodeJPEG(image: CGImage, quality: CGFloat) throws -> Data {
        let dest = NSMutableData()
        guard let cgDest = CGImageDestinationCreateWithData(
            dest, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw ExportError.encodeFailed }
        CGImageDestinationAddImage(cgDest, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(cgDest) else { throw ExportError.encodeFailed }
        return dest as Data
    }

    private static func buildPDFWithEmbeddedImage(imageData: Data, mediaBox: CGRect) throws -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { throw ExportError.encodeFailed }

        var box = mediaBox
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ExportError.encodeFailed
        }

        guard let imgSrc = CGImageSourceCreateWithData(imageData as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(imgSrc, 0, nil)
        else { throw ExportError.encodeFailed }

        ctx.beginPDFPage(nil)
        ctx.draw(img, in: box)
        ctx.endPDFPage()
        ctx.closePDF()

        return pdfData as Data
    }
}
