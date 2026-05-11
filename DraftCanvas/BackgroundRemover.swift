import Vision
import CoreImage
import AppKit

enum BackgroundRemovalError: Error, LocalizedError {
    case imageDecodeFailed
    case noSubjectFound
    case visionFailed(underlying: Error)
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:   return "画像ファイルを読み込めませんでした"
        case .noSubjectFound:      return "画像から主体を検出できませんでした"
        case .visionFailed(let e): return "背景除去に失敗しました: \(e.localizedDescription)"
        case .encodeFailed:        return "結果画像の保存に失敗しました"
        }
    }
}

enum BackgroundRemover {
    static func process(data: Data) async throws -> Data {
        guard let cgImage = makeCGImage(from: data) else {
            throw BackgroundRemovalError.imageDecodeFailed
        }
        return try await Task.detached(priority: .userInitiated) {
            try runVision(cgImage: cgImage)
        }.value
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return cg
    }

    private static func runVision(cgImage: CGImage) throws -> Data {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.visionFailed(underlying: error)
        }

        guard let observation = request.results?.first else {
            throw BackgroundRemovalError.noSubjectFound
        }

        let instances = observation.allInstances
        guard !instances.isEmpty else {
            throw BackgroundRemovalError.noSubjectFound
        }

        let maskedBuffer: CVPixelBuffer
        do {
            maskedBuffer = try observation.generateMaskedImage(
                ofInstances: instances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw BackgroundRemovalError.visionFailed(underlying: error)
        }

        return try encodeAsPNG(pixelBuffer: maskedBuffer)
    }

    private static func encodeAsPNG(pixelBuffer: CVPixelBuffer) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw BackgroundRemovalError.encodeFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw BackgroundRemovalError.encodeFailed
        }
        return pngData
    }
}
