import Vision
import CoreImage
import AppKit

enum BackgroundRemovalError: Error, LocalizedError {
    case imageDecodeFailed
    case noSubjectFound
    case visionFailed(underlying: Error)
    case maskGenerationFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:    return "画像ファイルを読み込めませんでした"
        case .noSubjectFound:       return "画像から主体を検出できませんでした"
        case .visionFailed(let e):  return "背景除去に失敗しました: \(e.localizedDescription)"
        case .maskGenerationFailed: return "マスクの生成に失敗しました"
        case .encodeFailed:         return "結果画像の保存に失敗しました"
        }
    }
}

enum BackgroundRemover {

    // MARK: - Session

    // Holds Vision results so post-processing (edgeStrength adjustment) can run
    // without repeating the Vision inference.
    struct MaskSession: @unchecked Sendable {
        let originalCI: CIImage       // orientation-correct original
        let guidedMaskCI: CIImage     // mask post-Guided Filter (pre-rendered, cached)
        let extent: CGRect
        let ciCtx: CIContext
        let sRGB: CGColorSpace
    }

    // MARK: - Public API

    /// Runs Vision inference and returns a session for real-time edgeStrength adjustment.
    static func extractMask(from data: Data) async throws -> MaskSession {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let rawCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw BackgroundRemovalError.imageDecodeFailed }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up

        return try await Task.detached(priority: .userInitiated) {
            try Self.runExtract(raw: rawCGImage, orientation: orientation)
        }.value
    }

    /// Applies edgeStrength post-processing to a cached session. Fast — no Vision inference.
    static func apply(session: MaskSession, edgeStrength: Double) throws -> Data {
        var maskCI = session.guidedMaskCI

        // edgeStrength 0.0→0.5: erode (shrink foreground, tighter cutout)
        // edgeStrength 0.5: center, no morphology
        // edgeStrength 0.5→1.0: dilate (expand foreground, looser cutout)
        let maxRadius: Double = 10.0
        let morphRadius = abs(edgeStrength - 0.5) * 2.0 * maxRadius
        if morphRadius > 0.5 {
            let filterName = edgeStrength < 0.5 ? "CIMorphologyMinimum" : "CIMorphologyMaximum"
            maskCI = maskCI
                .applyingFilter(filterName, parameters: ["inputRadius": morphRadius])
                .cropped(to: session.extent)
        }

        // Light anti-aliasing blur at edges regardless of morphology
        maskCI = maskCI
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.5])
            .cropped(to: session.extent)

        let composite = session.originalCI
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: maskCI,
                kCIInputBackgroundImageKey: CIImage.empty()
            ])
            .cropped(to: session.extent)

        guard let resultCG = session.ciCtx.createCGImage(
            composite, from: session.extent, format: .RGBA8, colorSpace: session.sRGB
        ) else { throw BackgroundRemovalError.encodeFailed }

        let rep = NSBitmapImageRep(cgImage: resultCG)
        guard let png = rep.representation(using: .png, properties: [:])
        else { throw BackgroundRemovalError.encodeFailed }
        return png
    }

    /// Convenience: extract + apply in one call (for non-interactive use).
    static func process(data: Data, edgeStrength: Double = 0.5) async throws -> Data {
        let session = try await extractMask(from: data)
        return try apply(session: session, edgeStrength: edgeStrength)
    }

    // MARK: - Private

    private static func runExtract(raw: CGImage, orientation: CGImagePropertyOrientation) throws -> MaskSession {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciCtx = CIContext(options: [
            .workingColorSpace: sRGB,
            .outputColorSpace: sRGB
        ])

        // Apply EXIF orientation
        let originalCI = CIImage(cgImage: raw).oriented(orientation)
        let extent = originalCI.extent

        let cgForVision: CGImage
        if orientation == .up {
            cgForVision = raw
        } else {
            guard let cg = ciCtx.createCGImage(originalCI, from: extent, format: .RGBA8, colorSpace: sRGB)
            else { throw BackgroundRemovalError.imageDecodeFailed }
            cgForVision = cg
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgForVision, options: [:])
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

        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
        } catch {
            throw BackgroundRemovalError.maskGenerationFailed
        }

        var maskCI = CIImage(cvPixelBuffer: maskBuffer)

        // Scale if Vision returned a different resolution
        let sx = extent.width / maskCI.extent.width
        let sy = extent.height / maskCI.extent.height
        if abs(sx - 1.0) > 0.01 || abs(sy - 1.0) > 0.01 {
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        // Guided Filter: align mask edges to color boundaries (applied once, cached)
        if let guided = CIFilter(name: "CIGuidedFilter") {
            guided.setValue(maskCI, forKey: kCIInputImageKey)
            guided.setValue(originalCI, forKey: "inputGuideImage")
            guided.setValue(NSNumber(value: 5), forKey: "inputRadius")
            guided.setValue(NSNumber(value: 0.01), forKey: "inputEpsilon")
            if let out = guided.outputImage {
                maskCI = out.cropped(to: extent)
            }
        }

        // Render to CGImage to cache the Guided Filter result — makes real-time
        // edgeStrength adjustment fast (only Gaussian blur + composite per frame).
        guard let guidedCG = ciCtx.createCGImage(maskCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw BackgroundRemovalError.maskGenerationFailed }
        let guidedMaskCI = CIImage(cgImage: guidedCG)

        return MaskSession(
            originalCI: originalCI,
            guidedMaskCI: guidedMaskCI,
            extent: extent,
            ciCtx: ciCtx,
            sRGB: sRGB
        )
    }
}
