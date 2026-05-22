import CoreImage

// TODO: Sendable 整理 — DetectedInstance / ExtractionSession は内部の CIImage / CGImage が
//       non-Sendable なため @unchecked Sendable を使用している。
//       将来的に actor isolation や structured concurrency に移行する際に見直すこと。

extension MaterialExtractor {

    enum InstanceSource: String, Sendable {
        case vision, cca, grouped, user, merged, split
    }

    struct DetectedInstance: Identifiable, @unchecked Sendable {
        let id: UUID
        var source: InstanceSource
        /// CIImage 正規化 bounding box（左下原点, 0..1）
        var normalizedBoundingBox: CGRect
        /// CIImage 座標系ピクセル bounding box（左下原点）
        var imageBoundingBox: CGRect
        /// インスタンスマスク（extent = フル画像の extent）
        var maskCI: CIImage
    }

    struct ExtractionSession: @unchecked Sendable {
        let originalCI: CIImage
        let originalCG: CGImage
        let extent: CGRect
        let imagePixelSize: CGSize
        let instances: [DetectedInstance]
        let ciCtx: CIContext
        let sRGB: CGColorSpace
    }
}
