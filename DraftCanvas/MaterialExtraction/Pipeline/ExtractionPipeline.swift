import Foundation
import CoreImage
import AppKit
import Vision

enum ExtractionPipeline {
    static func run(raw: CGImage, orientation: CGImagePropertyOrientation) throws -> MaterialExtractor.ExtractionSession {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciCtx = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

        let originalCI = CIImage(cgImage: raw).oriented(orientation)
        let extent = originalCI.extent
        let imagePixelSize = CGSize(width: extent.width, height: extent.height)

        // 512px に縮小して処理
        let maxSide: CGFloat = 512
        let scale = min(maxSide / extent.width, maxSide / extent.height, 1.0)

        let scaledCI = originalCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgSmall = ciCtx.createCGImage(
            scaledCI, from: scaledCI.extent, format: .RGBA8, colorSpace: sRGB
        ) else { throw MaterialExtractionError.imageDecodeFailed }

        // Vision インスタンス検出（失敗しても空配列で継続）
        let visionStage = VisionInstancesStage()
        let visionInsts = visionStage.run(.init(
            cgImage: cgSmall,
            extent: extent,
            imagePixelSize: imagePixelSize
        ))

        // CCA インスタンス検出
        let ccaStage = CCAInstancesStage()
        let ccaInsts = try ccaStage.run(.init(
            raw: cgSmall,
            extent: extent,
            imagePixelSize: imagePixelSize,
            scale: scale
        ))

        // IoU によるマージ
        let mergeStage = MergeByIoUStage()
        let merged = try mergeStage.run(.init(
            visionInstances: visionInsts,
            ccaInstances: ccaInsts
        ))

        // 小素材の近接グループ化
        let groupStage = GroupSmallNearbyStage()
        let instances = try groupStage.run(.init(
            instances: merged,
            imageSize: imagePixelSize,
            extent: extent
        ))

        guard !instances.isEmpty else { throw MaterialExtractionError.noInstancesFound }

        guard let originalCG = ciCtx.createCGImage(originalCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw MaterialExtractionError.imageDecodeFailed }

        return MaterialExtractor.ExtractionSession(
            originalCI: originalCI, originalCG: originalCG, extent: extent,
            imagePixelSize: imagePixelSize, instances: instances, ciCtx: ciCtx, sRGB: sRGB
        )
    }
}
