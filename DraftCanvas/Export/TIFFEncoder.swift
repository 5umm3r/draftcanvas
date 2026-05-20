import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TIFFEncoder {
    static func encode(
        pngData: Data,
        dpi: ExportDPI,
        compression: TIFFCompression
    ) throws -> Data {
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ExportError.decodeFailed }

        let converted = cgImage

        let dest = NSMutableData()
        guard let cgDest = CGImageDestinationCreateWithData(
            dest, UTType.tiff.identifier as CFString, 1, nil
        ) else { throw ExportError.encodeFailed }

        // LZW = 5 in TIFF spec
        let compressionValue: NSNumber
        switch compression {
        case .lzw: compressionValue = 5
        }

        let dpiNum = NSNumber(value: dpi.rawValue)
        let tiffDict: CFDictionary = [
            kCGImagePropertyTIFFCompression: compressionValue,
            kCGImagePropertyTIFFXResolution: dpiNum,
            kCGImagePropertyTIFFYResolution: dpiNum,
            kCGImagePropertyTIFFResolutionUnit: NSNumber(value: 2)
        ] as CFDictionary

        let props: CFDictionary = [
            kCGImagePropertyDPIWidth: dpiNum,
            kCGImagePropertyDPIHeight: dpiNum,
            kCGImagePropertyTIFFDictionary: tiffDict
        ] as CFDictionary

        CGImageDestinationAddImage(cgDest, converted, props)
        guard CGImageDestinationFinalize(cgDest) else { throw ExportError.encodeFailed }
        return dest as Data
    }
}
