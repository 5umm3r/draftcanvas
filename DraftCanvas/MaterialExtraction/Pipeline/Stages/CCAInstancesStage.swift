import CoreImage

/// CCA（Connected Component Analysis）を使って前景インスタンスを検出する Stage
struct CCAInstancesStage: ExtractionStage {
    struct Input {
        let raw: CGImage
        let extent: CGRect
        let imagePixelSize: CGSize
        let scale: CGFloat
    }
    typealias Output = [MaterialExtractor.DetectedInstance]

    func run(_ input: Input) throws -> [MaterialExtractor.DetectedInstance] {
        guard let provider = input.raw.dataProvider,
              let cfData = provider.data,
              let ptr = CFDataGetBytePtr(cfData) else {
            throw MaterialExtractionError.imageDecodeFailed
        }

        let w = input.raw.width, h = input.raw.height, bpr = input.raw.bytesPerRow

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

        var instances: [MaterialExtractor.DetectedInstance] = []
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
                .transformed(by: CGAffineTransform(scaleX: 1.0 / input.scale, y: 1.0 / input.scale))
                .cropped(to: input.extent)

            // CIImage 座標（左下原点）で bounding box 計算
            let nx = CGFloat(bbox.minC) / CGFloat(w)
            let ny = CGFloat(h - 1 - bbox.maxR) / CGFloat(h)
            let nw = CGFloat(bbox.maxC - bbox.minC + 1) / CGFloat(w)
            let nh = CGFloat(bbox.maxR - bbox.minR + 1) / CGFloat(h)
            let normalizedBox = CGRect(x: nx, y: ny, width: nw, height: nh)
            let imageBoundingBox = CGRect(
                x: normalizedBox.minX * input.imagePixelSize.width,
                y: normalizedBox.minY * input.imagePixelSize.height,
                width:  normalizedBox.width  * input.imagePixelSize.width,
                height: normalizedBox.height * input.imagePixelSize.height
            )

            instances.append(MaterialExtractor.DetectedInstance(
                id: UUID(),
                source: .cca,
                normalizedBoundingBox: normalizedBox,
                imageBoundingBox: imageBoundingBox,
                maskCI: maskCI
            ))
        }

        return instances
    }

    private func makeLabelMaskCG(labels: [Int32], targetLabel: Int32, width: Int, height: Int) -> CGImage? {
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
