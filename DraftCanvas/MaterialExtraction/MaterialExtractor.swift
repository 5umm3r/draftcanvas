import CoreImage
import AppKit
import Vision

/// MaterialExtractor のファサード。
/// 公開 API はすべてここに集約し、パイプライン処理は ExtractionPipeline に委譲する。
enum MaterialExtractor {

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
            try ExtractionPipeline.run(raw: rawCG, orientation: orientation)
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

    // MARK: - Private helpers (processUserInstance から呼ばれる)

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
}
