import AppKit

// MARK: - NSView

final class CropCanvasNSView: NSView {
    var image: NSImage
    var cropRect: CGRect
    var template: AspectTemplate
    weak var coordinator: CropCanvasView.Coordinator?

    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var cachedCGImage: CGImage?

    private enum HandleIndex: Int {
        case topLeft = 0
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left
    }

    private enum DragKind {
        case none
        case move
        case handle(HandleIndex)
    }

    private var dragKind: DragKind = .none
    private var dragStartViewPoint: CGPoint = .zero
    private var dragStartCropRect: CGRect = .zero

    init(image: NSImage, cropRect: CGRect, template: AspectTemplate) {
        self.image = image
        self.cropRect = cropRect
        self.template = template
        self.cachedCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        super.init(frame: .zero)
        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnify)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleMagnify(_ r: NSMagnificationGestureRecognizer) {
        zoom = min(4.0, max(0.25, zoom * (1 + r.magnification)))
        r.magnification = 0
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Template

    func applyTemplate() {
        let pixSize = imagePixelSize()
        guard pixSize.width > 0, pixSize.height > 0 else { return }
        let fullRect = CGRect(origin: .zero, size: pixSize)
        let newRect: CGRect
        if let ratio = template.ratio {
            // 現在 cropRect の中心を維持するのが理想だが、はみ出すと困るので
            // まず最大内接矩形を計算し、現在の中心に寄せてからクランプする
            let base = CropEditorSheet.largestInscribed(ratio: ratio, in: fullRect)
            var r = base
            let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
            r.origin.x = center.x - r.width / 2
            r.origin.y = center.y - r.height / 2
            newRect = clampToImage(r)
        } else {
            newRect = cropRect.isEmpty ? fullRect : cropRect
        }
        cropRect = newRect
        coordinator?.commitCropRect(newRect)
    }

    // MARK: - Coordinate helpers

    private var imageRect: CGRect {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }
        let boundsSize = bounds.size
        let scale = min(boundsSize.width / imgSize.width, boundsSize.height / imgSize.height) * zoom
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let x = (boundsSize.width - drawW) / 2 + panOffset.x
        let y = (boundsSize.height - drawH) / 2 + panOffset.y
        return CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    private func imagePixelSize() -> CGSize {
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let ph = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            if pw > 0, ph > 0 { return CGSize(width: pw, height: ph) }
        }
        return image.size
    }

    // 画像ピクセル座標 (top-left origin) → view 座標 (bottom-left origin)
    private func toViewRect(_ imgRect: CGRect) -> CGRect {
        let r = imageRect
        let pixSize = imagePixelSize()
        guard pixSize.width > 0, pixSize.height > 0 else { return .zero }
        let scaleX = r.width / pixSize.width
        let scaleY = r.height / pixSize.height
        let viewY = r.minY + (pixSize.height - imgRect.maxY) * scaleY
        return CGRect(
            x: r.minX + imgRect.minX * scaleX,
            y: viewY,
            width: imgRect.width * scaleX,
            height: imgRect.height * scaleY
        )
    }

    // view 座標 → 画像ピクセル座標
    private func toImageRect(_ viewRect: CGRect) -> CGRect {
        let r = imageRect
        let pixSize = imagePixelSize()
        guard r.width > 0, r.height > 0 else { return .zero }
        let scaleX = pixSize.width / r.width
        let scaleY = pixSize.height / r.height
        let imgY = pixSize.height - (viewRect.maxY - r.minY) * scaleY
        return CGRect(
            x: (viewRect.minX - r.minX) * scaleX,
            y: imgY,
            width: viewRect.width * scaleX,
            height: viewRect.height * scaleY
        )
    }

    private func toImagePoint(_ vp: CGPoint) -> CGPoint {
        let r = imageRect
        guard r.width > 0, r.height > 0 else { return .zero }
        let pixSize = imagePixelSize()
        let px = (vp.x - r.minX) / r.width * pixSize.width
        let py = (1 - (vp.y - r.minY) / r.height) * pixSize.height
        return CGPoint(x: px, y: py)
    }

    private func clampToImage(_ rect: CGRect) -> CGRect {
        let pixSize = imagePixelSize()
        var r = rect
        if r.width > pixSize.width { r.size.width = pixSize.width }
        if r.height > pixSize.height { r.size.height = pixSize.height }
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > pixSize.width { r.origin.x = pixSize.width - r.width }
        if r.maxY > pixSize.height { r.origin.y = pixSize.height - r.height }
        return r
    }

    private func handlePoints(for vRect: CGRect) -> [CGPoint] {
        let mx = vRect.midX, my = vRect.midY
        return [
            CGPoint(x: vRect.minX, y: vRect.maxY), // topLeft
            CGPoint(x: mx, y: vRect.maxY),         // top
            CGPoint(x: vRect.maxX, y: vRect.maxY), // topRight
            CGPoint(x: vRect.maxX, y: my),         // right
            CGPoint(x: vRect.maxX, y: vRect.minY), // bottomRight
            CGPoint(x: mx, y: vRect.minY),         // bottom
            CGPoint(x: vRect.minX, y: vRect.minY), // bottomLeft
            CGPoint(x: vRect.minX, y: my),         // left
        ]
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // チェッカーボード背景
        let tileSize: CGFloat = 12
        let light = NSColor(white: 0.82, alpha: 1).cgColor
        let dark = NSColor(white: 0.65, alpha: 1).cgColor
        let cols = Int(ceil(bounds.width / tileSize))
        let rows = Int(ceil(bounds.height / tileSize))
        for row in 0 ..< rows {
            for col in 0 ..< cols {
                ctx.setFillColor((row + col) % 2 == 0 ? light : dark)
                ctx.fill(CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize))
            }
        }

        let r = imageRect
        guard r.width > 0, r.height > 0 else { return }

        if let cgImage = cachedCGImage {
            ctx.draw(cgImage, in: r)
        }

        let vCropRect = toViewRect(cropRect)

        // 外側暗オーバーレイ
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(r)
        path.addRect(vCropRect)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // 三分割グリッド
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        let third1X = vCropRect.minX + vCropRect.width / 3
        let third2X = vCropRect.minX + vCropRect.width * 2 / 3
        let third1Y = vCropRect.minY + vCropRect.height / 3
        let third2Y = vCropRect.minY + vCropRect.height * 2 / 3
        ctx.move(to: CGPoint(x: third1X, y: vCropRect.minY))
        ctx.addLine(to: CGPoint(x: third1X, y: vCropRect.maxY))
        ctx.move(to: CGPoint(x: third2X, y: vCropRect.minY))
        ctx.addLine(to: CGPoint(x: third2X, y: vCropRect.maxY))
        ctx.move(to: CGPoint(x: vCropRect.minX, y: third1Y))
        ctx.addLine(to: CGPoint(x: vCropRect.maxX, y: third1Y))
        ctx.move(to: CGPoint(x: vCropRect.minX, y: third2Y))
        ctx.addLine(to: CGPoint(x: vCropRect.maxX, y: third2Y))
        ctx.strokePath()
        ctx.restoreGState()

        // 選択矩形枠
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(vCropRect)

        // ハンドル 8個
        let handleRadius: CGFloat = 6
        for p in handlePoints(for: vCropRect) {
            let rect = CGRect(x: p.x - handleRadius, y: p.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: rect)
        }

    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let vCropRect = toViewRect(cropRect)
        let hitRadius: CGFloat = 8

        // ハンドル hit test
        var hit: HandleIndex? = nil
        for (i, p) in handlePoints(for: vCropRect).enumerated() {
            let dx = vp.x - p.x
            let dy = vp.y - p.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                hit = HandleIndex(rawValue: i)
                break
            }
        }

        if let h = hit {
            dragKind = .handle(h)
        } else if vCropRect.contains(vp) {
            dragKind = .move
        } else {
            dragKind = .none
            return
        }

        dragStartViewPoint = vp
        dragStartCropRect = cropRect
    }

    override func mouseDragged(with event: NSEvent) {
        if case .none = dragKind { return }
        performDrag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        if case .none = dragKind {
            dragKind = .none
            return
        }
        performDrag(to: convert(event.locationInWindow, from: nil))
        dragKind = .none
        coordinator?.commitCropRect(cropRect)
        needsDisplay = true
    }

    private func performDrag(to vp: CGPoint) {
        let r = imageRect
        let pixSize = imagePixelSize()
        guard r.width > 0, r.height > 0, pixSize.width > 0, pixSize.height > 0 else { return }

        let viewToImageX = pixSize.width / r.width
        let viewToImageY = pixSize.height / r.height
        // view 座標の delta を画像座標に変換。Y は view と image で反転している
        let dxView = vp.x - dragStartViewPoint.x
        let dyView = vp.y - dragStartViewPoint.y
        let dxImg = dxView * viewToImageX
        let dyImg = -dyView * viewToImageY  // view の上方向 = image の上方向 = image y の減少

        switch dragKind {
        case .none:
            return
        case .move:
            var newRect = dragStartCropRect
            newRect.origin.x += dxImg
            newRect.origin.y += dyImg
            cropRect = clampToImage(newRect)
        case .handle(let h):
            cropRect = resizedRect(from: dragStartCropRect, handle: h, dxImg: dxImg, dyImg: dyImg)
        }
        coordinator?.commitCropRect(cropRect)
        needsDisplay = true
    }

    private func resizedRect(from start: CGRect, handle: HandleIndex, dxImg: CGFloat, dyImg: CGFloat) -> CGRect {
        let pixSize = imagePixelSize()
        let minSize: CGFloat = 8

        // start の各エッジ。image 座標は top-left origin なので minY = top, maxY = bottom
        var left = start.minX
        var top = start.minY
        var right = start.maxX
        var bottom = start.maxY

        // ハンドルに応じてエッジを移動
        switch handle {
        case .topLeft:
            left += dxImg
            top += dyImg
        case .top:
            top += dyImg
        case .topRight:
            right += dxImg
            top += dyImg
        case .right:
            right += dxImg
        case .bottomRight:
            right += dxImg
            bottom += dyImg
        case .bottom:
            bottom += dyImg
        case .bottomLeft:
            left += dxImg
            bottom += dyImg
        case .left:
            left += dxImg
        }

        // 最小サイズと反転防止
        if right - left < minSize {
            switch handle {
            case .topLeft, .bottomLeft, .left:
                left = right - minSize
            default:
                right = left + minSize
            }
        }
        if bottom - top < minSize {
            switch handle {
            case .topLeft, .topRight, .top:
                top = bottom - minSize
            default:
                bottom = top + minSize
            }
        }

        var newRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)

        // 比固定
        if let ratio = template.ratio {
            // ハンドル種別で固定点と可変軸を決める
            let widthChange = abs(newRect.width - start.width)
            let heightChange = abs(newRect.height - start.height)
            let edgeOnly: Bool = (handle == .top || handle == .bottom || handle == .left || handle == .right)

            var w: CGFloat
            var h: CGFloat

            if edgeOnly {
                // エッジハンドル: 動かした軸を主軸として他方を比から計算
                if handle == .left || handle == .right {
                    w = newRect.width
                    h = w / ratio
                } else {
                    h = newRect.height
                    w = h * ratio
                }
            } else {
                // コーナーハンドル: 大きい変化量を主軸とする
                if widthChange >= heightChange {
                    w = newRect.width
                    h = w / ratio
                } else {
                    h = newRect.height
                    w = h * ratio
                }
            }

            // 固定点 (反対側のコーナー or エッジの中点) を維持
            let anchor: CGPoint
            switch handle {
            case .topLeft:      anchor = CGPoint(x: start.maxX, y: start.maxY)  // 右下固定
            case .top:          anchor = CGPoint(x: start.midX, y: start.maxY)  // 下辺中央固定
            case .topRight:     anchor = CGPoint(x: start.minX, y: start.maxY)  // 左下固定
            case .right:        anchor = CGPoint(x: start.minX, y: start.midY)  // 左辺中央固定
            case .bottomRight:  anchor = CGPoint(x: start.minX, y: start.minY)  // 左上固定
            case .bottom:       anchor = CGPoint(x: start.midX, y: start.minY)  // 上辺中央固定
            case .bottomLeft:   anchor = CGPoint(x: start.maxX, y: start.minY)  // 右上固定
            case .left:         anchor = CGPoint(x: start.maxX, y: start.midY)  // 右辺中央固定
            }

            // anchor から見て newRect がどちら向きに伸びるかを決める
            switch handle {
            case .topLeft:
                newRect = CGRect(x: anchor.x - w, y: anchor.y - h, width: w, height: h)
            case .top:
                newRect = CGRect(x: anchor.x - w / 2, y: anchor.y - h, width: w, height: h)
            case .topRight:
                newRect = CGRect(x: anchor.x, y: anchor.y - h, width: w, height: h)
            case .right:
                newRect = CGRect(x: anchor.x, y: anchor.y - h / 2, width: w, height: h)
            case .bottomRight:
                newRect = CGRect(x: anchor.x, y: anchor.y, width: w, height: h)
            case .bottom:
                newRect = CGRect(x: anchor.x - w / 2, y: anchor.y, width: w, height: h)
            case .bottomLeft:
                newRect = CGRect(x: anchor.x - w, y: anchor.y, width: w, height: h)
            case .left:
                newRect = CGRect(x: anchor.x - w, y: anchor.y - h / 2, width: w, height: h)
            }
        }

        // 画像境界でクランプ。比固定時はサイズを縮小してアンカーを維持
        if let _ = template.ratio {
            newRect = clampPreservingRatio(newRect, anchorHandle: handle, start: start, pixSize: pixSize)
        } else {
            // 自由形式: そのままクランプ（サイズ縮小もあり得る）
            if newRect.minX < 0 {
                newRect.size.width += newRect.minX
                newRect.origin.x = 0
            }
            if newRect.minY < 0 {
                newRect.size.height += newRect.minY
                newRect.origin.y = 0
            }
            if newRect.maxX > pixSize.width {
                newRect.size.width = pixSize.width - newRect.minX
            }
            if newRect.maxY > pixSize.height {
                newRect.size.height = pixSize.height - newRect.minY
            }
        }

        // 最小サイズ再保証
        if newRect.width < minSize { newRect.size.width = minSize }
        if newRect.height < minSize { newRect.size.height = minSize }
        return newRect
    }

    private func clampPreservingRatio(_ rect: CGRect, anchorHandle: HandleIndex, start: CGRect, pixSize: CGSize) -> CGRect {
        guard let ratio = template.ratio else { return rect }
        var w = rect.width
        var h = rect.height

        // anchor 位置（固定点）を改めて算出
        let anchor: CGPoint
        switch anchorHandle {
        case .topLeft:      anchor = CGPoint(x: start.maxX, y: start.maxY)
        case .top:          anchor = CGPoint(x: start.midX, y: start.maxY)
        case .topRight:     anchor = CGPoint(x: start.minX, y: start.maxY)
        case .right:        anchor = CGPoint(x: start.minX, y: start.midY)
        case .bottomRight:  anchor = CGPoint(x: start.minX, y: start.minY)
        case .bottom:       anchor = CGPoint(x: start.midX, y: start.minY)
        case .bottomLeft:   anchor = CGPoint(x: start.maxX, y: start.minY)
        case .left:         anchor = CGPoint(x: start.maxX, y: start.midY)
        }

        // 各方向にどれだけ伸ばせるか (anchor から境界までの距離)
        // 左右と上下それぞれで最大幅・高さを算出
        var maxW: CGFloat = pixSize.width
        var maxH: CGFloat = pixSize.height

        switch anchorHandle {
        case .topLeft, .bottomLeft, .left:
            // anchor は右側 → 左に伸びる
            maxW = anchor.x
        case .topRight, .bottomRight, .right:
            // anchor は左側 → 右に伸びる
            maxW = pixSize.width - anchor.x
        case .top:
            // anchor は中央下、左右対称に伸びる
            maxW = min(anchor.x, pixSize.width - anchor.x) * 2
        case .bottom:
            maxW = min(anchor.x, pixSize.width - anchor.x) * 2
        }

        switch anchorHandle {
        case .topLeft, .topRight, .top:
            // anchor は下 → 上に伸びる
            maxH = anchor.y
        case .bottomLeft, .bottomRight, .bottom:
            // anchor は上 → 下に伸びる
            maxH = pixSize.height - anchor.y
        case .left, .right:
            // anchor は左右中央、上下対称に伸びる
            maxH = min(anchor.y, pixSize.height - anchor.y) * 2
        }

        // 比を保ちつつ縮小
        if w > maxW {
            w = maxW
            h = w / ratio
        }
        if h > maxH {
            h = maxH
            w = h * ratio
        }

        // anchor を維持して再配置
        var newRect = CGRect.zero
        switch anchorHandle {
        case .topLeft:
            newRect = CGRect(x: anchor.x - w, y: anchor.y - h, width: w, height: h)
        case .top:
            newRect = CGRect(x: anchor.x - w / 2, y: anchor.y - h, width: w, height: h)
        case .topRight:
            newRect = CGRect(x: anchor.x, y: anchor.y - h, width: w, height: h)
        case .right:
            newRect = CGRect(x: anchor.x, y: anchor.y - h / 2, width: w, height: h)
        case .bottomRight:
            newRect = CGRect(x: anchor.x, y: anchor.y, width: w, height: h)
        case .bottom:
            newRect = CGRect(x: anchor.x - w / 2, y: anchor.y, width: w, height: h)
        case .bottomLeft:
            newRect = CGRect(x: anchor.x - w, y: anchor.y, width: w, height: h)
        case .left:
            newRect = CGRect(x: anchor.x - w, y: anchor.y - h / 2, width: w, height: h)
        }
        return newRect
    }

    // MARK: - Tracking / scroll

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        needsDisplay = true
    }
}
