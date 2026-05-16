import CoreImage
import AppKit

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

    struct DetectedInstance: Identifiable, @unchecked Sendable {
        let id: UUID = UUID()
        let visionInstanceIndex: Int
        /// CIImage 正規化 bounding box（左下原点, 0..1）
        let normalizedBoundingBox: CGRect
        /// CIImage 座標系ピクセル bounding box（左下原点）
        let imageBoundingBox: CGRect
        /// インスタンスマスク（extent = フル画像の extent）
        let maskCI: CIImage
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

    static func detect(from data: Data) async throws -> ExtractionSession {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let rawCG = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MaterialExtractionError.imageDecodeFailed }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        return try await Task.detached(priority: .userInitiated) {
            try Self.runCCA(raw: rawCG, orientation: orientation)
        }.value
    }

    /// 1 インスタンスを透過 PNG として返す。cropToBoundingBox=true でインスタンス境界にクロップ。
    static func renderInstancePNG(
        session: ExtractionSession,
        instance: DetectedInstance,
        cropToBoundingBox: Bool = true
    ) throws -> Data {
        let blurredMask = instance.maskCI
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.5])
            .cropped(to: session.extent)

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

        guard let resultCG = session.ciCtx.createCGImage(
            composite, from: renderExtent, format: .RGBA8, colorSpace: session.sRGB
        ) else { throw MaterialExtractionError.encodeFailed }

        let rep = NSBitmapImageRep(cgImage: resultCG)
        guard let png = rep.representation(using: .png, properties: [:])
        else { throw MaterialExtractionError.encodeFailed }
        return png
    }

    // MARK: - CCA（Connected Component Analysis）

    private static func runCCA(raw: CGImage, orientation: CGImagePropertyOrientation) throws -> ExtractionSession {
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

        guard let provider = cgSmall.dataProvider,
              let cfData = provider.data,
              let ptr = CFDataGetBytePtr(cfData) else {
            throw MaterialExtractionError.imageDecodeFailed
        }

        let w = cgSmall.width, h = cgSmall.height, bpr = cgSmall.bytesPerRow

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
        let n = UInt32(bgSamplesR.count)
        let bgR = bgSamplesR.sorted()[bgSamplesR.count / 2]
        let bgG = bgSamplesG.sorted()[bgSamplesG.count / 2]
        let bgB = bgSamplesB.sorted()[bgSamplesB.count / 2]
        _ = n

        // 背景色との色距離（squared）でマスク生成
        let thresholdSq: UInt32 = 30 * 30
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

        // BFS 連結成分ラベリング
        var labels = [Int32](repeating: -1, count: w * h)
        var labelCount: Int32 = 0
        struct BBox { var minR, maxR, minC, maxC: Int }
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
                    if r < bbox.minR { bbox.minR = r }; if r > bbox.maxR { bbox.maxR = r }
                    if c < bbox.minC { bbox.minC = c }; if c > bbox.maxC { bbox.maxC = c }
                    for (dr, dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nr = r + dr, nc = c + dc
                        guard nr >= 0, nr < h, nc >= 0, nc < w else { continue }
                        let nidx = nr * w + nc
                        guard fgMask[nidx], labels[nidx] < 0 else { continue }
                        labels[nidx] = label
                        queue.append((nr, nc))
                    }
                }
                bboxes.append(bbox)
            }
        }

        // 面積フィルタ（0.05% 未満はノイズ、20% 超は背景アーティファクト）
        let minAreaRatio: Double = 0.0005
        let maxAreaRatio: Double = 0.20
        let totalPx = w * h

        var instances: [DetectedInstance] = []
        for (labelIdx, bbox) in bboxes.enumerated() {
            let area = (bbox.maxR - bbox.minR + 1) * (bbox.maxC - bbox.minC + 1)
            let areaRatio = Double(area) / Double(totalPx)
            guard areaRatio >= minAreaRatio, areaRatio <= maxAreaRatio else { continue }

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
                visionInstanceIndex: instances.count,
                normalizedBoundingBox: normalizedBox,
                imageBoundingBox: imageBoundingBox,
                maskCI: maskCI
            ))
        }

        guard !instances.isEmpty else { throw MaterialExtractionError.noInstancesFound }

        guard let originalCG = ciCtx.createCGImage(originalCI, from: extent, format: .RGBA8, colorSpace: sRGB)
        else { throw MaterialExtractionError.imageDecodeFailed }

        return ExtractionSession(
            originalCI: originalCI, originalCG: originalCG, extent: extent,
            imagePixelSize: imagePixelSize, instances: instances, ciCtx: ciCtx, sRGB: sRGB
        )
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
}
