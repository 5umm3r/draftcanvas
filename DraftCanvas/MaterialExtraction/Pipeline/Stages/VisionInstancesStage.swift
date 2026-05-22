import CoreImage
import Vision

/// Vision を使って前景インスタンスを検出する Stage
struct VisionInstancesStage: ExtractionStage {
    struct Input {
        let cgImage: CGImage
        let extent: CGRect
        let imagePixelSize: CGSize
    }
    typealias Output = [MaterialExtractor.DetectedInstance]

    /// 失敗時は空配列を返す（throws しない）
    func run(_ input: Input) -> [MaterialExtractor.DetectedInstance] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: input.cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observation = request.results?.first else { return [] }
        let allInstances = observation.allInstances
        guard !allInstances.isEmpty else { return [] }

        let ciCtxLocal = CIContext()
        let bbStage = BoundingBoxStage()
        var results: [MaterialExtractor.DetectedInstance] = []

        for i in allInstances {
            let maskBuffer: CVPixelBuffer
            do {
                maskBuffer = try observation.generateScaledMaskForImage(forInstances: [i], from: handler)
            } catch {
                continue
            }

            var maskCI = CIImage(cvPixelBuffer: maskBuffer)

            // extent に合わせてスケール補正
            let sx = input.imagePixelSize.width / maskCI.extent.width
            let sy = input.imagePixelSize.height / maskCI.extent.height
            if abs(sx - 1.0) > 0.01 || abs(sy - 1.0) > 0.01 {
                maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            }
            maskCI = maskCI.cropped(to: input.extent)

            // マスクのピクセルを走査して bbox を計算
            let bbInput = BoundingBoxStage.Input(
                maskCI: maskCI,
                ciCtx: ciCtxLocal,
                imagePixelSize: input.imagePixelSize
            )
            guard let normalizedBox = (try? bbStage.run(bbInput)) ?? nil else { continue }

            let imageBoundingBox = CGRect(
                x: normalizedBox.minX * input.imagePixelSize.width,
                y: normalizedBox.minY * input.imagePixelSize.height,
                width:  normalizedBox.width  * input.imagePixelSize.width,
                height: normalizedBox.height * input.imagePixelSize.height
            )

            results.append(MaterialExtractor.DetectedInstance(
                id: UUID(),
                source: .vision,
                normalizedBoundingBox: normalizedBox,
                imageBoundingBox: imageBoundingBox,
                maskCI: maskCI
            ))
        }

        return results
    }
}
