import CoreImage
import AppKit
import Vision

enum MaterialExtractionError: Error, LocalizedError {
    case imageDecodeFailed
    case noInstancesFound
    case maskGenerationFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:    return String(localized: "画像ファイルを読み込めませんでした")
        case .noInstancesFound:     return String(localized: "素材を検出できませんでした")
        case .maskGenerationFailed: return String(localized: "マスクの生成に失敗しました")
        case .encodeFailed:         return String(localized: "結果画像の保存に失敗しました")
        }
    }
}

enum MaterialExtractor {

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

    // MARK: - Public API

    /// ユーザーが矩形ドラッグで手動追加した DetectedInstance を生成する
    static func makeUserInstance(
        imageBBox: CGRect,
        imagePixelSize: CGSize,
        extent: CGRect
    ) -> DetectedInstance {
        let nx = imageBBox.minX / imagePixelSize.width
        let ny = imageBBox.minY / imagePixelSize.height
        let nw = imageBBox.width / imagePixelSize.width
        let nh = imageBBox.height / imagePixelSize.height
        let normalizedBox = CGRect(x: nx, y: ny, width: nw, height: nh)

        // extent 全体を黒で塗りつぶし、bbox 内だけ白を合成したマスクを作成。
        // bbox のみ白い CIImage だと CIGaussianBlur の edge extension で bbox 外に白が広がり、
        // extent 全体が白くなって背景が切り抜かれなくなるバグを防ぐ。
        let bboxInExtent = CGRect(
            x: extent.minX + imageBBox.minX,
            y: extent.minY + imageBBox.minY,
            width: imageBBox.width,
            height: imageBBox.height
        )
        let blackBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)
        let whiteFG = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: bboxInExtent)
        let maskCI = whiteFG.composited(over: blackBG)

        return DetectedInstance(
            id: UUID(),
            source: .user,
            normalizedBoundingBox: normalizedBox,
            imageBoundingBox: imageBBox,
            maskCI: maskCI
        )
    }

    /// `.user` instance の矩形ソリッドマスクを背景除去マスクに置換する。
    /// Vision 優先、失敗時 CCA fallback、両方失敗時は元 instance を返す（矩形クロップ）。
    static func processUserInstance(
        session: ExtractionSession,
        instance: DetectedInstance
    ) -> DetectedInstance {
        guard instance.source == .user else { return instance }

        let extent = session.extent
        let bbox = instance.imageBoundingBox
        let bboxInExtent = CGRect(
            x: extent.minX + bbox.minX,
            y: extent.minY + bbox.minY,
            width: bbox.width,
            height: bbox.height
        )
        let blackBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)

        // Vision 優先
        if let visionMask = visionMaskForUserInstance(session: session, instance: instance) {
            // bbox 外の前景を除去してから extent 全体を黒で埋める
            let clipped = visionMask.cropped(to: bboxInExtent).composited(over: blackBG)
            return DetectedInstance(
                id: instance.id,
                source: .vision,
                normalizedBoundingBox: instance.normalizedBoundingBox,
                imageBoundingBox: instance.imageBoundingBox,
                maskCI: clipped
            )
        }

        // CCA fallback
        if let ccaMask = ccaMaskForUserInstance(session: session, instance: instance) {
            let finalMask = ccaMask.composited(over: blackBG)
            return DetectedInstance(
                id: instance.id,
                source: .user,
                normalizedBoundingBox: instance.normalizedBoundingBox,
                imageBoundingBox: instance.imageBoundingBox,
                maskCI: finalMask
            )
        }

        return instance
    }

    private static func visionMaskForUserInstance(
        session: ExtractionSession,
        instance: DetectedInstance
    ) -> CIImage? {
        let extent = session.extent
        // session.ciCtx を共有すると Metal GPU リソースがメインスレッドの描画と競合するためローカルで生成
        let ciCtx = CIContext(options: [.workingColorSpace: session.sRGB, .outputColorSpace: session.sRGB])
        let scale = min(512.0 / extent.width, 512.0 / extent.height, 1.0)
        let scaledCI = session.originalCI
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgSmall = ciCtx.createCGImage(
            scaledCI, from: scaledCI.extent, format: .RGBA8, colorSpace: session.sRGB
        ) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgSmall, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler
            )
        } catch { return nil }

        var maskCI = CIImage(cvPixelBuffer: maskBuffer)
        let sx = extent.width / maskCI.extent.width
        let sy = extent.height / maskCI.extent.height
        if abs(sx - 1.0) > 0.01 || abs(sy - 1.0) > 0.01 {
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        maskCI = maskCI.cropped(to: extent)

        // bbox 内に前景が 0.5% 以上あるか確認（空マスクを CCA に委ねる）
        let bbox = instance.imageBoundingBox
        let bboxInExtent = CGRect(
            x: extent.minX + bbox.minX,
            y: extent.minY + bbox.minY,
            width: bbox.width,
            height: bbox.height
        )
        guard let checkCG = ciCtx.createCGImage(
            maskCI.cropped(to: bboxInExtent),
            from: bboxInExtent,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        ),
        let checkData = checkCG.dataProvider?.data,
        let checkPtr = CFDataGetBytePtr(checkData) else { return maskCI }

        let pixelCount = checkCG.width * checkCG.height
        var fgCount = 0
        for i in 0..<pixelCount where checkPtr[i] > 128 { fgCount += 1 }
        guard fgCount >= max(1, pixelCount / 200) else { return nil }

        return maskCI
    }

    private static func ccaMaskForUserInstance(
        session: ExtractionSession,
        instance: DetectedInstance
    ) -> CIImage? {
        let cg = session.originalCG
        let origW = cg.width, origH = cg.height
        let bbox = instance.imageBoundingBox
        let extent = session.extent

        let w = Int(bbox.width.rounded())
        let h = Int(bbox.height.rounded())
        guard w > 4, h > 4 else { return nil }

        let cgMinX = Int(bbox.minX.rounded())
        let cgMinY = Int((CGFloat(origH) - bbox.maxY).rounded())
        guard cgMinX >= 0, cgMinY >= 0,
              cgMinX + w <= origW,
              cgMinY + h <= origH else { return nil }

        guard let provider = cg.dataProvider,
              let cfData = provider.data,
              let ptr = CFDataGetBytePtr(cfData) else { return nil }
        let bpr = cg.bytesPerRow

        // 全画像縁から背景色推定
        var bgSamplesR: [UInt32] = [], bgSamplesG: [UInt32] = [], bgSamplesB: [UInt32] = []
        let hStep = max(1, origW / 16), vStep = max(1, origH / 16)
        for col in stride(from: 0, through: origW - 1, by: hStep) {
            for edgeRow in [0, origH - 1] {
                let base = edgeRow * bpr + col * 4
                bgSamplesR.append(UInt32(ptr[base]))
                bgSamplesG.append(UInt32(ptr[base + 1]))
                bgSamplesB.append(UInt32(ptr[base + 2]))
            }
        }
        for row in stride(from: 0, through: origH - 1, by: vStep) {
            for edgeCol in [0, origW - 1] {
                let base = row * bpr + edgeCol * 4
                bgSamplesR.append(UInt32(ptr[base]))
                bgSamplesG.append(UInt32(ptr[base + 1]))
                bgSamplesB.append(UInt32(ptr[base + 2]))
            }
        }
        guard !bgSamplesR.isEmpty else { return nil }

        let bgR = bgSamplesR.sorted()[bgSamplesR.count / 2]
        let bgG = bgSamplesG.sorted()[bgSamplesG.count / 2]
        let bgB = bgSamplesB.sorted()[bgSamplesB.count / 2]
        let bgMeanR = Double(bgSamplesR.reduce(0, +)) / Double(bgSamplesR.count)
        let bgMeanG = Double(bgSamplesG.reduce(0, +)) / Double(bgSamplesG.count)
        let bgMeanB = Double(bgSamplesB.reduce(0, +)) / Double(bgSamplesB.count)
        let bgVarR = bgSamplesR.map { pow(Double($0) - bgMeanR, 2) }.reduce(0, +) / Double(bgSamplesR.count)
        let bgVarG = bgSamplesG.map { pow(Double($0) - bgMeanG, 2) }.reduce(0, +) / Double(bgSamplesG.count)
        let bgVarB = bgSamplesB.map { pow(Double($0) - bgMeanB, 2) }.reduce(0, +) / Double(bgSamplesB.count)
        let thresholdSq = UInt32(pow(max(15.0, min(45.0, (bgVarR + bgVarG + bgVarB).squareRoot() * 2.5)), 2))

        var fgMask = [Bool](repeating: false, count: w * h)
        for row in 0..<h {
            let rowBase = (cgMinY + row) * bpr
            for col in 0..<w {
                let base = rowBase + (cgMinX + col) * 4
                let r = UInt32(ptr[base]), g = UInt32(ptr[base + 1])
                let b = UInt32(ptr[base + 2]), a = UInt32(ptr[base + 3])
                guard a > 10 else { continue }
                let dr = r > bgR ? r - bgR : bgR - r
                let dg = g > bgG ? g - bgG : bgG - g
                let db = b > bgB ? b - bgB : bgB - b
                fgMask[row * w + col] = dr * dr + dg * dg + db * db > thresholdSq
            }
        }

        let kernelHalf = max(1, min(w, h) / 200)
        var dilated = fgMask
        for row in 0..<h {
            for col in 0..<w {
                guard !fgMask[row * w + col] else { continue }
                outer: for dr in -kernelHalf...kernelHalf {
                    for dc in -kernelHalf...kernelHalf {
                        let nr = row + dr, nc = col + dc
                        guard nr >= 0, nr < h, nc >= 0, nc < w else { continue }
                        if fgMask[nr * w + nc] { dilated[row * w + col] = true; break outer }
                    }
                }
            }
        }
        var closed = dilated
        for row in 0..<h {
            for col in 0..<w {
                guard dilated[row * w + col] else { continue }
                var shouldErase = false
                for dr in -kernelHalf...kernelHalf {
                    if shouldErase { break }
                    for dc in -kernelHalf...kernelHalf {
                        let nr = row + dr, nc = col + dc
                        guard nr >= 0, nr < h, nc >= 0, nc < w else { shouldErase = true; break }
                        if !dilated[nr * w + nc] { shouldErase = true; break }
                    }
                }
                if shouldErase { closed[row * w + col] = false }
            }
        }
        fgMask = closed

        var labels = [Int32](repeating: -1, count: w * h)
        var labelCount: Int32 = 0
        var labelPixelCounts: [Int] = []
        for startRow in 0..<h {
            for startCol in 0..<w {
                let startIdx = startRow * w + startCol
                guard fgMask[startIdx], labels[startIdx] < 0 else { continue }
                let label = labelCount; labelCount += 1
                var queue = [(Int, Int)](); queue.reserveCapacity(512)
                queue.append((startRow, startCol))
                labels[startIdx] = label
                var pixelCount = 0
                var head = 0
                while head < queue.count {
                    let (r, c) = queue[head]; head += 1
                    pixelCount += 1
                    for dr in -1...1 {
                        for dc in -1...1 {
                            guard dr != 0 || dc != 0 else { continue }
                            let nr = r + dr, nc = c + dc
                            guard nr >= 0, nr < h, nc >= 0, nc < w else { continue }
                            let nidx = nr * w + nc
                            guard fgMask[nidx], labels[nidx] < 0 else { continue }
                            labels[nidx] = label
                            queue.append((nr, nc))
                        }
                    }
                }
                labelPixelCounts.append(pixelCount)
            }
        }
        guard !labelPixelCounts.isEmpty else { return nil }

        // 全連結成分合算（ドット集合・散在素材をまとめて保持）
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ),
        let rawPtr = ctx.data else { return nil }
        let maskPtr = rawPtr.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) { maskPtr[i] = labels[i] >= 0 ? 255 : 0 }
        guard let maskCG = ctx.makeImage() else { return nil }

        let bboxInExtent = CGRect(
            x: extent.minX + bbox.minX,
            y: extent.minY + bbox.minY,
            width: bbox.width,
            height: bbox.height
        )
        let scaleX = bboxInExtent.width / CGFloat(w)
        let scaleY = bboxInExtent.height / CGFloat(h)
        // samplingNearest でバイリニア補間を抑制しバイナリマスクのエッジ中間値を防ぐ
        return CIImage(cgImage: maskCG)
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: bboxInExtent.minX, y: bboxInExtent.minY))
    }

    // MARK: - Split

    struct SplitLine {
        enum Axis { case vertical, horizontal }
        let axis: Axis
        let position: CGFloat  // CIImage 座標系（vertical なら x、horizontal なら y）
    }

    /// 1 つの DetectedInstance を分割線で2つに分割する
    static func splitInstance(
        _ inst: DetectedInstance,
        line: SplitLine,
        imagePixelSize: CGSize,
        extent: CGRect
    ) -> (DetectedInstance, DetectedInstance) {
        let bbox = inst.imageBoundingBox
        let pos = line.position

        let (bboxA, bboxB): (CGRect, CGRect)
        switch line.axis {
        case .vertical:
            let clampedX = max(bbox.minX + 1, min(bbox.maxX - 1, pos))
            bboxA = CGRect(x: bbox.minX, y: bbox.minY,
                           width: clampedX - bbox.minX, height: bbox.height)
            bboxB = CGRect(x: clampedX, y: bbox.minY,
                           width: bbox.maxX - clampedX, height: bbox.height)
        case .horizontal:
            let clampedY = max(bbox.minY + 1, min(bbox.maxY - 1, pos))
            bboxA = CGRect(x: bbox.minX, y: bbox.minY,
                           width: bbox.width, height: clampedY - bbox.minY)
            bboxB = CGRect(x: bbox.minX, y: clampedY,
                           width: bbox.width, height: bbox.maxY - clampedY)
        }

        let imgW = imagePixelSize.width, imgH = imagePixelSize.height
        func normalize(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX / imgW, y: r.minY / imgH,
                   width: r.width / imgW, height: r.height / imgH)
        }

        // extent.origin が (0,0) 前提でクロップ（runPipeline 確認済み）
        func cropMask(_ b: CGRect) -> CIImage {
            let bboxInExtent = CGRect(
                x: extent.minX + b.minX,
                y: extent.minY + b.minY,
                width: b.width,
                height: b.height
            )
            return inst.maskCI.cropped(to: bboxInExtent)
        }

        let maskA = cropMask(bboxA)
        let maskB = cropMask(bboxB)

        let instA = DetectedInstance(id: UUID(), source: .split,
            normalizedBoundingBox: normalize(bboxA),
            imageBoundingBox: bboxA, maskCI: maskA)
        let instB = DetectedInstance(id: UUID(), source: .split,
            normalizedBoundingBox: normalize(bboxB),
            imageBoundingBox: bboxB, maskCI: maskB)

        return (instA, instB)
    }

    /// 複数の DetectedInstance を1つに結合する（ユーザー操作による手動結合用）
    static func mergeInstances(
        _ list: [DetectedInstance],
        extent: CGRect
    ) -> DetectedInstance {
        precondition(!list.isEmpty)
        guard list.count > 1 else { return list[0] }

        // bbox union
        let unionBBox = list.dropFirst().reduce(list[0].imageBoundingBox) { $0.union($1.imageBoundingBox) }
        let unionNorm = list.dropFirst().reduce(list[0].normalizedBoundingBox) { $0.union($1.normalizedBoundingBox) }

        // マスク合成: CIMaximumCompositing で OR
        var mergedMask = list[0].maskCI
        for inst in list.dropFirst() {
            let filter = CIFilter(name: "CIMaximumCompositing")
            filter?.setValue(inst.maskCI, forKey: kCIInputImageKey)
            filter?.setValue(mergedMask, forKey: kCIInputBackgroundImageKey)
            if let output = filter?.outputImage {
                mergedMask = output
            }
            // filter が nil の場合は mergedMask をそのまま維持（マスク欠落を防ぐ）
        }
        mergedMask = mergedMask.cropped(to: extent)

        return DetectedInstance(
            id: UUID(),
            source: .merged,
            normalizedBoundingBox: unionNorm,
            imageBoundingBox: unionBBox,
            maskCI: mergedMask
        )
    }

    static func detect(from data: Data) async throws -> ExtractionSession {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let rawCG = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MaterialExtractionError.imageDecodeFailed }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        return try await Task.detached(priority: .userInitiated) {
            try Self.runPipeline(raw: rawCG, orientation: orientation)
        }.value
    }

    /// 1 インスタンスを透過 PNG として返す。cropToBoundingBox=true でインスタンス境界にクロップ。
    /// ciCtx を渡すとそれを使用する。nil の場合 session.ciCtx を使う（メインスレッドからの呼び出し限定）。
    static func renderInstancePNG(
        session: ExtractionSession,
        instance: DetectedInstance,
        cropToBoundingBox: Bool = true,
        ciCtx: CIContext? = nil
    ) throws -> Data {
        let ctx = ciCtx ?? session.ciCtx
        // user instance はソリッドマスクなので blur をかけると edge extension で背景が残るため除外
        let blurredMask: CIImage
        if instance.source == .user {
            blurredMask = instance.maskCI.cropped(to: session.extent)
        } else {
            blurredMask = instance.maskCI
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.5])
                .cropped(to: session.extent)
        }

        var composite = session.originalCI
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: blurredMask,
                kCIInputBackgroundImageKey: CIImage.empty()
            ])
            .cropped(to: session.extent)

        let renderExtent: CGRect
        if cropToBoundingBox {
            let bboxInExtent = CGRect(
                x: session.extent.minX + instance.imageBoundingBox.minX,
                y: session.extent.minY + instance.imageBoundingBox.minY,
                width:  instance.imageBoundingBox.width,
                height: instance.imageBoundingBox.height
            )
            composite = composite.cropped(to: bboxInExtent)
            renderExtent = bboxInExtent
        } else {
            renderExtent = session.extent
        }

        guard let resultCG = ctx.createCGImage(
            composite, from: renderExtent, format: .RGBA8, colorSpace: session.sRGB
        ) else { throw MaterialExtractionError.encodeFailed }

        let rep = NSBitmapImageRep(cgImage: resultCG)
        guard let png = rep.representation(using: .png, properties: [:])
        else { throw MaterialExtractionError.encodeFailed }
        return png
    }

    // MARK: - Pipeline

    private static func runPipeline(raw: CGImage, orientation: CGImagePropertyOrientation) throws -> ExtractionSession {
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
        let visionInsts = runVisionInstances(
            cgImage: cgSmall,
            extent: extent,
            imagePixelSize: imagePixelSize
        )

        // CCA インスタンス検出
        let ccaInsts = try runCCAInstances(
            raw: cgSmall, orientation: .up,
            ciCtx: ciCtx, sRGB: sRGB,
            originalCI: originalCI, extent: extent, imagePixelSize: imagePixelSize,
            scale: scale
        )

        // IoU によるマージ
        let merged = mergeByIoU(visionInstances: visionInsts, ccaInstances: ccaInsts)

        // 小素材の近接グループ化
        let instances = groupSmallNearby(merged, imageSize: imagePixelSize, extent: extent)

        guard !instances.isEmpty else { throw MaterialExtractionError.noInstancesFound }

        guard let originalCG = ciCtx.createCGImage(originalCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw MaterialExtractionError.imageDecodeFailed }

        return ExtractionSession(
            originalCI: originalCI, originalCG: originalCG, extent: extent,
            imagePixelSize: imagePixelSize, instances: instances, ciCtx: ciCtx, sRGB: sRGB
        )
    }

    // MARK: - Vision インスタンス検出

    private static func runVisionInstances(
        cgImage: CGImage,
        extent: CGRect,
        imagePixelSize: CGSize
    ) -> [DetectedInstance] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observation = request.results?.first else { return [] }
        let allInstances = observation.allInstances
        guard !allInstances.isEmpty else { return [] }

        let ciCtxLocal = CIContext()
        var results: [DetectedInstance] = []

        for i in allInstances {
            let maskBuffer: CVPixelBuffer
            do {
                maskBuffer = try observation.generateScaledMaskForImage(forInstances: [i], from: handler)
            } catch {
                continue
            }

            var maskCI = CIImage(cvPixelBuffer: maskBuffer)

            // extent に合わせてスケール補正
            let sx = imagePixelSize.width / maskCI.extent.width
            let sy = imagePixelSize.height / maskCI.extent.height
            if abs(sx - 1.0) > 0.01 || abs(sy - 1.0) > 0.01 {
                maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            }
            maskCI = maskCI.cropped(to: extent)

            // マスクのピクセルを走査して bbox を計算
            let normalizedBox = computeBoundingBox(maskCI: maskCI, ciCtx: ciCtxLocal, imagePixelSize: imagePixelSize)
            guard let normalizedBox = normalizedBox else { continue }

            let imageBoundingBox = CGRect(
                x: normalizedBox.minX * imagePixelSize.width,
                y: normalizedBox.minY * imagePixelSize.height,
                width:  normalizedBox.width  * imagePixelSize.width,
                height: normalizedBox.height * imagePixelSize.height
            )

            results.append(DetectedInstance(
                id: UUID(),
                source: .vision,
                normalizedBoundingBox: normalizedBox,
                imageBoundingBox: imageBoundingBox,
                maskCI: maskCI
            ))
        }

        return results
    }

    /// マスク CIImage のアルファ >= 128 のピクセルから正規化 bounding box を計算する
    private static func computeBoundingBox(
        maskCI: CIImage,
        ciCtx: CIContext,
        imagePixelSize: CGSize
    ) -> CGRect? {
        // グレースケールで CGImage に変換（マスクは輝度がアルファ相当）
        guard let cgMask = ciCtx.createCGImage(
            maskCI, from: maskCI.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()
        ) else { return nil }

        let w = cgMask.width, h = cgMask.height
        guard w > 0, h > 0,
              let provider = cgMask.dataProvider,
              let cfData = provider.data,
              let ptr = CFDataGetBytePtr(cfData) else { return nil }

        let bpr = cgMask.bytesPerRow
        var minRow = h, maxRow = -1, minCol = w, maxCol = -1

        for row in 0..<h {
            for col in 0..<w {
                let idx = row * bpr + col
                if ptr[idx] >= 128 {
                    if row < minRow { minRow = row }
                    if row > maxRow { maxRow = row }
                    if col < minCol { minCol = col }
                    if col > maxCol { maxCol = col }
                }
            }
        }

        guard maxRow >= minRow, maxCol >= minCol else { return nil }

        // CGImage 座標（左上原点）→ CIImage 座標（左下原点）に変換
        let nx = CGFloat(minCol) / CGFloat(w)
        let ny = CGFloat(h - 1 - maxRow) / CGFloat(h)
        let nw = CGFloat(maxCol - minCol + 1) / CGFloat(w)
        let nh = CGFloat(maxRow - minRow + 1) / CGFloat(h)
        return CGRect(x: nx, y: ny, width: nw, height: nh)
    }

    // MARK: - CCA（Connected Component Analysis）

    private static func runCCAInstances(
        raw: CGImage, orientation: CGImagePropertyOrientation,
        ciCtx: CIContext, sRGB: CGColorSpace,
        originalCI: CIImage, extent: CGRect, imagePixelSize: CGSize,
        scale: CGFloat
    ) throws -> [DetectedInstance] {
        guard let provider = raw.dataProvider,
              let cfData = provider.data,
              let ptr = CFDataGetBytePtr(cfData) else {
            throw MaterialExtractionError.imageDecodeFailed
        }

        let w = raw.width, h = raw.height, bpr = raw.bytesPerRow

        // 縁（4辺）から均等にサンプリングして背景色を推定
        var bgSamplesR: [UInt32] = [], bgSamplesG: [UInt32] = [], bgSamplesB: [UInt32] = []
        let hStep = max(1, w / 16), vStep = max(1, h / 16)
        for col in stride(from: 0, through: w - 1, by: hStep) {
            for edgeRow in [0, h - 1] {
                let base = edgeRow * bpr + col * 4
                bgSamplesR.append(UInt32(ptr[base]))
                bgSamplesG.append(UInt32(ptr[base + 1]))
                bgSamplesB.append(UInt32(ptr[base + 2]))
            }
        }
        for row in stride(from: 0, through: h - 1, by: vStep) {
            for edgeCol in [0, w - 1] {
                let base = row * bpr + edgeCol * 4
                bgSamplesR.append(UInt32(ptr[base]))
                bgSamplesG.append(UInt32(ptr[base + 1]))
                bgSamplesB.append(UInt32(ptr[base + 2]))
            }
        }
        // 中央値で外れ値（素材が縁にかかる場合）を除外
        let bgR = bgSamplesR.sorted()[bgSamplesR.count / 2]
        let bgG = bgSamplesG.sorted()[bgSamplesG.count / 2]
        let bgB = bgSamplesB.sorted()[bgSamplesB.count / 2]

        // 適応しきい値: 背景色の分散から動的に決定
        let bgMeanR = Double(bgSamplesR.reduce(0, +)) / Double(bgSamplesR.count)
        let bgMeanG = Double(bgSamplesG.reduce(0, +)) / Double(bgSamplesG.count)
        let bgMeanB = Double(bgSamplesB.reduce(0, +)) / Double(bgSamplesB.count)
        let bgVarR = bgSamplesR.map { pow(Double($0) - bgMeanR, 2) }.reduce(0, +) / Double(bgSamplesR.count)
        let bgVarG = bgSamplesG.map { pow(Double($0) - bgMeanG, 2) }.reduce(0, +) / Double(bgSamplesG.count)
        let bgVarB = bgSamplesB.map { pow(Double($0) - bgMeanB, 2) }.reduce(0, +) / Double(bgSamplesB.count)
        let bgStd = (bgVarR + bgVarG + bgVarB).squareRoot()
        let adaptiveThresh = max(15.0, min(45.0, bgStd * 2.5))
        let thresholdSq = UInt32(adaptiveThresh * adaptiveThresh)

        var fgMask = [Bool](repeating: false, count: w * h)
        for row in 0..<h {
            let rowBase = row * bpr
            for col in 0..<w {
                let base = rowBase + col * 4
                let r = UInt32(ptr[base]), g = UInt32(ptr[base + 1])
                let b = UInt32(ptr[base + 2]), a = UInt32(ptr[base + 3])
                guard a > 10 else { continue }
                let dr = r > bgR ? r - bgR : bgR - r
                let dg = g > bgG ? g - bgG : bgG - g
                let db = b > bgB ? b - bgB : bgB - b
                fgMask[row * w + col] = dr * dr + dg * dg + db * db > thresholdSq
            }
        }

        // morphological closing: dilation → erosion
        let kernelHalf = max(1, min(w, h) / 200)
        // dilation
        var dilated = fgMask
        for row in 0..<h {
            for col in 0..<w {
                guard !fgMask[row * w + col] else { continue }
                outer: for dr in -kernelHalf...kernelHalf {
                    for dc in -kernelHalf...kernelHalf {
                        let nr = row + dr, nc = col + dc
                        guard nr >= 0, nr < h, nc >= 0, nc < w else { continue }
                        if fgMask[nr * w + nc] { dilated[row * w + col] = true; break outer }
                    }
                }
            }
        }
        // erosion
        var closed = dilated
        for row in 0..<h {
            for col in 0..<w {
                guard dilated[row * w + col] else { continue }
                var shouldErase = false
                for dr in -kernelHalf...kernelHalf {
                    if shouldErase { break }
                    for dc in -kernelHalf...kernelHalf {
                        let nr = row + dr, nc = col + dc
                        guard nr >= 0, nr < h, nc >= 0, nc < w else {
                            shouldErase = true; break  // 境界外は背景とみなす
                        }
                        if !dilated[nr * w + nc] { shouldErase = true; break }
                    }
                }
                if shouldErase { closed[row * w + col] = false }
            }
        }
        fgMask = closed

        // BFS 連結成分ラベリング
        var labels = [Int32](repeating: -1, count: w * h)
        var labelCount: Int32 = 0
        struct BBox { var minR, maxR, minC, maxC: Int; var pixelCount: Int = 0 }
        var bboxes: [BBox] = []

        for startRow in 0..<h {
            for startCol in 0..<w {
                let startIdx = startRow * w + startCol
                guard fgMask[startIdx], labels[startIdx] < 0 else { continue }

                let label = labelCount; labelCount += 1
                var queue = [(Int, Int)](); queue.reserveCapacity(512)
                queue.append((startRow, startCol))
                labels[startIdx] = label
                var bbox = BBox(minR: startRow, maxR: startRow, minC: startCol, maxC: startCol)
                var head = 0

                while head < queue.count {
                    let (r, c) = queue[head]; head += 1
                    bbox.pixelCount += 1
                    if r < bbox.minR { bbox.minR = r }; if r > bbox.maxR { bbox.maxR = r }
                    if c < bbox.minC { bbox.minC = c }; if c > bbox.maxC { bbox.maxC = c }
                    for dr in -1...1 {
                        for dc in -1...1 {
                            guard dr != 0 || dc != 0 else { continue }
                            let nr = r + dr, nc = c + dc
                            guard nr >= 0, nr < h, nc >= 0, nc < w else { continue }
                            let nidx = nr * w + nc
                            guard fgMask[nidx], labels[nidx] < 0 else { continue }
                            labels[nidx] = label
                            queue.append((nr, nc))
                        }
                    }
                }
                bboxes.append(bbox)
            }
        }

        // 面積フィルタ（0.05% 未満はノイズ、45% 超は背景アーティファクト）
        let minAreaRatio: Double = 0.0005
        let maxAreaRatio: Double = 0.45
        let totalPx = w * h

        var instances: [DetectedInstance] = []
        for (labelIdx, bbox) in bboxes.enumerated() {
            let area = bbox.pixelCount  // bbox 矩形面積ではなく実ピクセル数
            let areaRatio = Double(area) / Double(totalPx)
            guard areaRatio >= minAreaRatio, areaRatio <= maxAreaRatio else { continue }
            if areaRatio > 0.30 {
                let touchesEdge = bbox.minR == 0 || bbox.minC == 0 || bbox.maxR == h - 1 || bbox.maxC == w - 1
                if touchesEdge { continue }
            }

            guard let maskCG = makeLabelMaskCG(
                labels: labels, targetLabel: Int32(labelIdx), width: w, height: h
            ) else { continue }

            // 元解像度にアップスケール（CCA のバイナリマスクはエッジ補正不要）
            let maskCI = CIImage(cgImage: maskCG)
                .transformed(by: CGAffineTransform(scaleX: 1.0 / scale, y: 1.0 / scale))
                .cropped(to: extent)

            // CIImage 座標（左下原点）で bounding box 計算
            let nx = CGFloat(bbox.minC) / CGFloat(w)
            let ny = CGFloat(h - 1 - bbox.maxR) / CGFloat(h)
            let nw = CGFloat(bbox.maxC - bbox.minC + 1) / CGFloat(w)
            let nh = CGFloat(bbox.maxR - bbox.minR + 1) / CGFloat(h)
            let normalizedBox = CGRect(x: nx, y: ny, width: nw, height: nh)
            let imageBoundingBox = CGRect(
                x: normalizedBox.minX * imagePixelSize.width,
                y: normalizedBox.minY * imagePixelSize.height,
                width:  normalizedBox.width  * imagePixelSize.width,
                height: normalizedBox.height * imagePixelSize.height
            )

            instances.append(DetectedInstance(
                id: UUID(),
                source: .cca,
                normalizedBoundingBox: normalizedBox,
                imageBoundingBox: imageBoundingBox,
                maskCI: maskCI
            ))
        }

        return instances
    }

    private static func makeLabelMaskCG(labels: [Int32], targetLabel: Int32, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        guard let rawPtr = ctx.data else { return nil }
        let ptr = rawPtr.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height) {
            ptr[i] = labels[i] == targetLabel ? 255 : 0
        }
        return ctx.makeImage()
    }

    // MARK: - Union-Find ヘルパー

    private static func findRoot(_ i: Int, _ parent: inout [Int]) -> Int {
        var x = i
        while parent[x] != x {
            parent[x] = parent[parent[x]]
            x = parent[x]
        }
        return x
    }

    private static func unionSets(_ a: Int, _ b: Int, _ parent: inout [Int]) {
        let ra = findRoot(a, &parent)
        let rb = findRoot(b, &parent)
        if ra != rb { parent[ra] = rb }
    }

    // MARK: - 小素材近接グループ化

    private static func groupSmallNearby(
        _ instances: [DetectedInstance],
        imageSize: CGSize,
        extent: CGRect
    ) -> [DetectedInstance] {
        let n = instances.count
        guard n > 0 else { return instances }

        // 1. 各 instance の対角長を計算
        let diags = instances.map { inst -> CGFloat in
            let w = inst.imageBoundingBox.width
            let h = inst.imageBoundingBox.height
            return sqrt(w * w + h * h)
        }

        // 2. medianD（対角長の中央値）を計算
        let sortedDiags = diags.sorted()
        let medianD = sortedDiags[sortedDiags.count / 2]

        // 3. 小素材判定
        let minSide = min(imageSize.width, imageSize.height)
        let isSmall = diags.map { d in
            d < medianD * 0.6 && d < minSide * 0.05
        }

        // 小素材インデックス一覧
        let smallIndices = (0..<n).filter { isSmall[$0] }

        // 4. 小素材が 1 個以下なら即返却
        guard smallIndices.count >= 2 else { return instances }

        // 小素材の中心座標
        let smallCenters = smallIndices.map { i -> CGPoint in
            let box = instances[i].imageBoundingBox
            return CGPoint(x: box.midX, y: box.midY)
        }

        // 各小素材と他の全小素材の最近傍距離を計算
        var nearestDists: [CGFloat] = []
        for i in 0..<smallCenters.count {
            var minDist = CGFloat.infinity
            for j in 0..<smallCenters.count {
                guard i != j else { continue }
                let dx = smallCenters[i].x - smallCenters[j].x
                let dy = smallCenters[i].y - smallCenters[j].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < minDist { minDist = dist }
            }
            if minDist < .infinity { nearestDists.append(minDist) }
        }

        guard !nearestDists.isEmpty else { return instances }

        let sortedNearestDists = nearestDists.sorted()
        let clusterDist = sortedNearestDists[sortedNearestDists.count / 2]
        let mergeDist = clusterDist * 1.8

        // 5. 距離 < mergeDist で Union-Find（小素材インデックス同士）
        var parent = [Int](0..<n)

        for ai in 0..<smallIndices.count {
            for bi in (ai + 1)..<smallIndices.count {
                let a = smallIndices[ai]
                let b = smallIndices[bi]
                let dx = smallCenters[ai].x - smallCenters[bi].x
                let dy = smallCenters[ai].y - smallCenters[bi].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < mergeDist {
                    unionSets(a, b, &parent)
                }
            }
        }

        // 6. グループ化した結果を DetectedInstance にまとめる
        var groups: [Int: [Int]] = [:]
        for i in smallIndices {
            let root = findRoot(i, &parent)
            groups[root, default: []].append(i)
        }

        var result: [DetectedInstance] = []

        // グループ化されない中・大素材はそのまま追加
        let groupedIndices = Set(smallIndices)
        for i in 0..<n {
            if !groupedIndices.contains(i) {
                result.append(instances[i])
            }
        }

        // グループ化された小素材を合成
        for (_, group) in groups {
            if group.count == 1 {
                // 単独小素材はそのまま
                result.append(instances[group[0]])
                continue
            }

            // bbox を union
            var unionBBox = instances[group[0]].imageBoundingBox
            for i in group.dropFirst() {
                unionBBox = unionBBox.union(instances[i].imageBoundingBox)
            }

            // maskCI を CIFilter.maximumCompositing() で合成
            var mergedMask = instances[group[0]].maskCI
            for i in group.dropFirst() {
                guard let filter = CIFilter(name: "CIMaximumCompositing") else { continue }
                filter.setValue(instances[i].maskCI, forKey: kCIInputImageKey)
                filter.setValue(mergedMask, forKey: kCIInputBackgroundImageKey)
                if let output = filter.outputImage {
                    mergedMask = output
                }
            }
            mergedMask = mergedMask.cropped(to: extent)

            // normalizedBoundingBox を再計算
            let normalizedBoundingBox = CGRect(
                x: unionBBox.minX / imageSize.width,
                y: unionBBox.minY / imageSize.height,
                width: unionBBox.width / imageSize.width,
                height: unionBBox.height / imageSize.height
            )

            result.append(DetectedInstance(
                id: UUID(),
                source: .grouped,
                normalizedBoundingBox: normalizedBoundingBox,
                imageBoundingBox: unionBBox,
                maskCI: mergedMask
            ))
        }

        return result
    }

    // MARK: - IoU マージ

    private static func mergeByIoU(
        visionInstances: [DetectedInstance],
        ccaInstances: [DetectedInstance]
    ) -> [DetectedInstance] {
        let all = visionInstances + ccaInstances
        let n = all.count
        guard n > 0 else { return [] }

        // IoU 計算
        func iou(_ a: CGRect, _ b: CGRect) -> Double {
            let intersection = a.intersection(b)
            if intersection.isNull { return 0 }
            let intersectionArea = Double(intersection.width * intersection.height)
            let unionArea = Double(a.width * a.height) + Double(b.width * b.height) - intersectionArea
            return unionArea > 0 ? intersectionArea / unionArea : 0
        }

        // Union-Find
        var parent = [Int](0..<n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                if iou(all[i].normalizedBoundingBox, all[j].normalizedBoundingBox) >= 0.30 {
                    unionSets(i, j, &parent)
                }
            }
        }

        // グループ化
        var groups: [Int: [Int]] = [:]
        for i in 0..<n {
            let root = findRoot(i, &parent)
            groups[root, default: []].append(i)
        }

        // 各グループから代表を選出
        var result: [DetectedInstance] = []
        for (_, group) in groups {
            // Vision インスタンスを優先、なければ CCA
            let visionInGroup = group.filter { all[$0].source == .vision }
            let candidates = visionInGroup.isEmpty ? group : visionInGroup
            // 面積が最大のものを代表に
            let rep = candidates.max(by: {
                let a = all[$0].normalizedBoundingBox
                let b = all[$1].normalizedBoundingBox
                return Double(a.width * a.height) < Double(b.width * b.height)
            })!
            result.append(all[rep])
        }

        return result
    }
}
