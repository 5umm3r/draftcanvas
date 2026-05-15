import Foundation
import AppKit

enum ImageVectorizationError: Error, LocalizedError {
    case imageDecodeFailed
    case conversionFailed(code: Int32)
    case previewRenderFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:        return L("画像の解析に失敗しました")
        case .conversionFailed(let c):  return L("ベクター変換に失敗しました (code: \(c))")
        case .previewRenderFailed:      return L("プレビュー画像の生成に失敗しました")
        }
    }
}

struct VectorizationOptions {
    var colorPrecision: Int32 = 6
    var filterSpeckle: Int32 = 4
    var cornerThreshold: Int32 = 60
    var lengthThreshold: Double = 4.0
    var spliceThreshold: Int32 = 45
    var layerDifference: Int32 = 16
    var mode: Int32 = 0   // 0=spline
    static let `default` = VectorizationOptions()
}

struct VectorizationResult {
    let svgData: Data
    let previewPNGData: Data
}

enum ImageVectorizer {

    static func process(data: Data, options: VectorizationOptions = .default) async throws -> VectorizationResult {
        try await Task.detached(priority: .userInitiated) {
            try runVtracer(data: data, options: options)
        }.value
    }

    private static func runVtracer(data: Data, options: VectorizationOptions) throws -> VectorizationResult {
        var params = VtracerParams(
            color_precision: options.colorPrecision,
            filter_speckle: options.filterSpeckle,
            corner_threshold: options.cornerThreshold,
            length_threshold: options.lengthThreshold,
            splice_threshold: options.spliceThreshold,
            layer_difference: options.layerDifference,
            mode: options.mode
        )

        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0

        let status: Int32 = data.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else { return 1 }
            return vtracer_convert(base, buf.count, &params, &outPtr, &outLen)
        }

        guard status == 0, let ptr = outPtr else {
            switch status {
            case 2: throw ImageVectorizationError.imageDecodeFailed
            default: throw ImageVectorizationError.conversionFailed(code: status)
            }
        }

        let svgData = Data(bytes: ptr, count: outLen)
        vtracer_free(ptr, outLen)

        guard let previewPNG = SVGRasterizer.rasterize(svgData: svgData) else {
            throw ImageVectorizationError.previewRenderFailed
        }
        return VectorizationResult(svgData: svgData, previewPNGData: previewPNG)
    }
}
