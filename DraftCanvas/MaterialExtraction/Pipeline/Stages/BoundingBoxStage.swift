import CoreImage

/// マスク CIImage のアルファ >= 128 のピクセルから正規化 bounding box を計算する Stage
struct BoundingBoxStage: ExtractionStage {
    struct Input {
        let maskCI: CIImage
        let ciCtx: CIContext
        let imagePixelSize: CGSize
    }
    typealias Output = CGRect?

    func run(_ input: Input) throws -> CGRect? {
        // グレースケールで CGImage に変換（マスクは輝度がアルファ相当）
        guard let cgMask = input.ciCtx.createCGImage(
            input.maskCI, from: input.maskCI.extent,
            format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()
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
}
