import Vision
import CoreImage
import AppKit

enum BackgroundRemovalError: Error, LocalizedError {
    case imageDecodeFailed
    case noSubjectFound
    case visionFailed(underlying: Error)
    case maskGenerationFailed
    case encodeFailed
    case modeUnavailable

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:    return String(localized: "画像ファイルを読み込めませんでした")
        case .noSubjectFound:       return String(localized: "画像から主体を検出できませんでした")
        case .visionFailed(let e):  return String(localized: "背景除去に失敗しました: \(e.localizedDescription)")
        case .maskGenerationFailed: return String(localized: "マスクの生成に失敗しました")
        case .encodeFailed:         return String(localized: "結果画像の保存に失敗しました")
        case .modeUnavailable:      return String(localized: "選択したモードのマスクを取得できませんでした")
        }
    }
}

enum BackgroundRemover {

    enum Mode: String, CaseIterable {
        case logo, photo
    }

    // MARK: - Session

    struct MaskSession: @unchecked Sendable {
        let originalCI: CIImage
        let logoMaskCI: CIImage?      // 色差ベース (白/単色背景向け)
        let photoMaskCI: CIImage?     // Vision ベース (写真向け、失敗時 nil)
        let initialMode: Mode         // 自動判定結果
        let extent: CGRect
        let ciCtx: CIContext
        let sRGB: CGColorSpace
    }

    // MARK: - Public API

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

    static func apply(session: MaskSession, edgeStrength: Double, mode: Mode) throws -> Data {
        guard let maskCIBase = (mode == .logo ? session.logoMaskCI : session.photoMaskCI) else {
            throw BackgroundRemovalError.modeUnavailable
        }
        var maskCI = maskCIBase

        let maxRadius: Double = 10.0
        let morphRadius = abs(edgeStrength - 0.5) * 2.0 * maxRadius
        if morphRadius > 0.5 {
            let filterName = edgeStrength < 0.5 ? "CIMorphologyMinimum" : "CIMorphologyMaximum"
            maskCI = maskCI
                .applyingFilter(filterName, parameters: ["inputRadius": morphRadius])
                .cropped(to: session.extent)
        }

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

    static func process(data: Data, edgeStrength: Double = 0.5) async throws -> Data {
        let session = try await extractMask(from: data)
        return try apply(session: session, edgeStrength: edgeStrength, mode: session.initialMode)
    }

    // MARK: - Private

    private static func runExtract(raw: CGImage, orientation: CGImagePropertyOrientation) throws -> MaskSession {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciCtx = CIContext(options: [
            .workingColorSpace: sRGB,
            .outputColorSpace: sRGB
        ])

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

        let initialMode = detectInitialMode(originalCI: originalCI, extent: extent, ciCtx: ciCtx, sRGB: sRGB)

        // ロゴモード: 色差ベース (常に試みる)
        let logoMaskCI = try? extractLogoMask(
            originalCI: originalCI, extent: extent, ciCtx: ciCtx, sRGB: sRGB
        )
        // 写真モード: Vision ベース (失敗しても nil で継続)
        let photoMaskCI = try? extractPhotoMask(
            cgForVision: cgForVision, originalCI: originalCI, extent: extent, ciCtx: ciCtx, sRGB: sRGB
        )

        guard logoMaskCI != nil || photoMaskCI != nil else {
            throw BackgroundRemovalError.maskGenerationFailed
        }

        let effectiveMode: Mode
        switch initialMode {
        case .logo:  effectiveMode = logoMaskCI != nil ? .logo : .photo
        case .photo: effectiveMode = photoMaskCI != nil ? .photo : .logo
        }

        return MaskSession(
            originalCI: originalCI,
            logoMaskCI: logoMaskCI,
            photoMaskCI: photoMaskCI,
            initialMode: effectiveMode,
            extent: extent,
            ciCtx: ciCtx,
            sRGB: sRGB
        )
    }

    // MARK: - Logo mask (color-difference based)

    private static func extractLogoMask(
        originalCI: CIImage,
        extent: CGRect,
        ciCtx: CIContext,
        sRGB: CGColorSpace
    ) throws -> CIImage {
        let bgColor = estimateBackgroundColor(originalCI: originalCI, extent: extent, ciCtx: ciCtx, sRGB: sRGB)

        guard
            let bgGen = CIFilter(name: "CIConstantColorGenerator", parameters: ["inputColor": bgColor]),
            let bgRaw = bgGen.outputImage
        else { throw BackgroundRemovalError.maskGenerationFailed }
        let bgImage = bgRaw.cropped(to: extent)

        guard
            let diffFilter = CIFilter(name: "CIColorAbsoluteDifference", parameters: [
                kCIInputImageKey: originalCI,
                "inputImage2": bgImage
            ]),
            let diffRaw = diffFilter.outputImage
        else { throw BackgroundRemovalError.maskGenerationFailed }
        let diffImage = diffRaw.cropped(to: extent)

        // RGB チャンネルの最大値をグレースケールマスクに
        var maskCI: CIImage
        if let maxFilter = CIFilter(name: "CIMaximumComponent", parameters: [kCIInputImageKey: diffImage]),
           let maxOut = maxFilter.outputImage {
            maskCI = maxOut.cropped(to: extent)
        } else {
            // フォールバック: R+G+B 平均
            let w = CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0)
            maskCI = diffImage.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": w, "inputGVector": w, "inputBVector": w,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]).cropped(to: extent)
        }

        // Soft threshold: コントラスト強調で前景/背景を分離
        if let controls = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: maskCI,
            "inputContrast": NSNumber(value: 6.0),
            "inputBrightness": NSNumber(value: -0.15)
        ]), let out = controls.outputImage {
            maskCI = out.cropped(to: extent)
        }

        // Guided Filter: エッジを元画像の色境界に合わせる
        if let guided = CIFilter(name: "CIGuidedFilter") {
            guided.setValue(maskCI, forKey: kCIInputImageKey)
            guided.setValue(originalCI, forKey: "inputGuideImage")
            guided.setValue(NSNumber(value: 5), forKey: "inputRadius")
            guided.setValue(NSNumber(value: 0.01), forKey: "inputEpsilon")
            if let out = guided.outputImage {
                maskCI = out.cropped(to: extent)
            }
        }

        guard let cachedCG = ciCtx.createCGImage(maskCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw BackgroundRemovalError.maskGenerationFailed }
        return CIImage(cgImage: cachedCG)
    }

    // MARK: - Photo mask (Vision based)

    private static func extractPhotoMask(
        cgForVision: CGImage,
        originalCI: CIImage,
        extent: CGRect,
        ciCtx: CIContext,
        sRGB: CGColorSpace
    ) throws -> CIImage {
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

        let sx = extent.width / maskCI.extent.width
        let sy = extent.height / maskCI.extent.height
        if abs(sx - 1.0) > 0.01 || abs(sy - 1.0) > 0.01 {
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        if let guided = CIFilter(name: "CIGuidedFilter") {
            guided.setValue(maskCI, forKey: kCIInputImageKey)
            guided.setValue(originalCI, forKey: "inputGuideImage")
            guided.setValue(NSNumber(value: 5), forKey: "inputRadius")
            guided.setValue(NSNumber(value: 0.01), forKey: "inputEpsilon")
            if let out = guided.outputImage {
                maskCI = out.cropped(to: extent)
            }
        }

        guard let cachedCG = ciCtx.createCGImage(maskCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw BackgroundRemovalError.maskGenerationFailed }
        return CIImage(cgImage: cachedCG)
    }

    // MARK: - Auto mode detection

    private static func detectInitialMode(
        originalCI: CIImage,
        extent: CGRect,
        ciCtx: CIContext,
        sRGB: CGColorSpace
    ) -> Mode {
        let side: CGFloat = max(4, min(32, extent.width * 0.05, extent.height * 0.05))
        let regions: [CGRect] = [
            CGRect(x: extent.minX, y: extent.minY, width: side, height: side),
            CGRect(x: extent.maxX - side, y: extent.minY, width: side, height: side),
            CGRect(x: extent.minX, y: extent.maxY - side, width: side, height: side),
            CGRect(x: extent.maxX - side, y: extent.maxY - side, width: side, height: side),
        ]

        var colors: [(r: Float, g: Float, b: Float)] = []
        for region in regions {
            if let c = sampleAverageColor(image: originalCI, region: region, ciCtx: ciCtx, sRGB: sRGB) {
                colors.append(c)
            }
        }
        guard colors.count >= 2 else { return .photo }

        // 四隅色差の最大値 — 小さければ単色背景 → logo
        var maxDiff: Float = 0
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                let dr = colors[i].r - colors[j].r
                let dg = colors[i].g - colors[j].g
                let db = colors[i].b - colors[j].b
                maxDiff = max(maxDiff, (dr * dr + dg * dg + db * db).squareRoot())
            }
        }
        return maxDiff < 0.15 ? .logo : .photo
    }

    // MARK: - Helpers

    private static func estimateBackgroundColor(
        originalCI: CIImage,
        extent: CGRect,
        ciCtx: CIContext,
        sRGB: CGColorSpace
    ) -> CIColor {
        let side: CGFloat = max(4, min(32, extent.width * 0.05, extent.height * 0.05))
        let regions: [CGRect] = [
            CGRect(x: extent.minX, y: extent.minY, width: side, height: side),
            CGRect(x: extent.maxX - side, y: extent.minY, width: side, height: side),
            CGRect(x: extent.minX, y: extent.maxY - side, width: side, height: side),
            CGRect(x: extent.maxX - side, y: extent.maxY - side, width: side, height: side),
        ]

        var reds: [Float] = [], greens: [Float] = [], blues: [Float] = []
        for region in regions {
            if let (r, g, b) = sampleAverageColor(image: originalCI, region: region, ciCtx: ciCtx, sRGB: sRGB) {
                reds.append(r); greens.append(g); blues.append(b)
            }
        }
        guard !reds.isEmpty else { return CIColor.white }

        func median(_ vals: [Float]) -> Float {
            let s = vals.sorted(); return s[s.count / 2]
        }
        return CIColor(
            red: CGFloat(median(reds)),
            green: CGFloat(median(greens)),
            blue: CGFloat(median(blues)),
            colorSpace: sRGB
        ) ?? CIColor.white
    }

    private static func sampleAverageColor(
        image: CIImage,
        region: CGRect,
        ciCtx: CIContext,
        sRGB: CGColorSpace
    ) -> (Float, Float, Float)? {
        guard
            let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: CIVector(cgRect: region)
            ]),
            let output = filter.outputImage
        else { return nil }

        var pixel = [Float](repeating: 0, count: 4)
        ciCtx.render(
            output,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: sRGB
        )
        return (pixel[0], pixel[1], pixel[2])
    }
}
