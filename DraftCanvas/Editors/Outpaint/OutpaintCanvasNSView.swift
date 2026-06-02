import AppKit

final class OutpaintCanvasNSView: NSView {
    var image: NSImage
    var insets: OutpaintInsets = .zero
    weak var coordinator: OutpaintCanvasView.Coordinator?

    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var cachedCGImage: CGImage?
    private let maxExpandPx: CGFloat = 2048

    private enum HandleIndex: Int {
        case topLeft = 0, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragKind {
        case none
        case handle(HandleIndex)
    }

    private var dragKind: DragKind = .none
    private var dragStartViewPoint: CGPoint = .zero
    private var dragStartInsets: OutpaintInsets = .zero

    init(image: NSImage) {
        self.image = image
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

    // MARK: - Coordinate helpers

    private func imagePixelSize() -> CGSize {
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let ph = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            if pw > 0, ph > 0 { return CGSize(width: pw, height: ph) }
        }
        return image.size
    }

    private let viewPadding: CGFloat = 40

    // 元画像の view 上描画領域（拡張含まない）
    private var imageRect: CGRect {
        let pixSize = imagePixelSize()
        let expandedPix = insets.expandedSize(from: pixSize)
        guard expandedPix.width > 0, expandedPix.height > 0 else { return .zero }

        let availW = max(1, bounds.width - viewPadding * 2)
        let availH = max(1, bounds.height - viewPadding * 2)
        let scale = min(availW / expandedPix.width, availH / expandedPix.height) * zoom
        let totalW = expandedPix.width * scale
        let totalH = expandedPix.height * scale

        let originX = (bounds.width - totalW) / 2 + panOffset.x
        let originY = (bounds.height - totalH) / 2 + panOffset.y

        let imgW = pixSize.width * scale
        let imgH = pixSize.height * scale
        let imgX = originX + insets.left * scale
        let imgY = originY + insets.bottom * scale

        return CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
    }

    // 拡張領域を含む全体の view 上描画領域
    private var extendedRect: CGRect {
        let pixSize = imagePixelSize()
        let expandedPix = insets.expandedSize(from: pixSize)
        guard expandedPix.width > 0, expandedPix.height > 0 else { return .zero }

        let availW = max(1, bounds.width - viewPadding * 2)
        let availH = max(1, bounds.height - viewPadding * 2)
        let scale = min(availW / expandedPix.width, availH / expandedPix.height) * zoom
        let totalW = expandedPix.width * scale
        let totalH = expandedPix.height * scale
        let originX = (bounds.width - totalW) / 2 + panOffset.x
        let originY = (bounds.height - totalH) / 2 + panOffset.y

        return CGRect(x: originX, y: originY, width: totalW, height: totalH)
    }

    private func viewScale() -> CGFloat {
        let pixSize = imagePixelSize()
        let expandedPix = insets.expandedSize(from: pixSize)
        guard expandedPix.width > 0, expandedPix.height > 0 else { return 1 }
        let availW = max(1, bounds.width - viewPadding * 2)
        let availH = max(1, bounds.height - viewPadding * 2)
        return min(availW / expandedPix.width, availH / expandedPix.height) * zoom
    }

    private func handlePoints(for ext: CGRect) -> [CGPoint] {
        let mx = ext.midX, my = ext.midY
        return [
            CGPoint(x: ext.minX, y: ext.maxY),  // topLeft
            CGPoint(x: mx, y: ext.maxY),         // top
            CGPoint(x: ext.maxX, y: ext.maxY),   // topRight
            CGPoint(x: ext.maxX, y: my),          // right
            CGPoint(x: ext.maxX, y: ext.minY),   // bottomRight
            CGPoint(x: mx, y: ext.minY),          // bottom
            CGPoint(x: ext.minX, y: ext.minY),   // bottomLeft
            CGPoint(x: ext.minX, y: my),          // left
        ]
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // ビュー背景
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(bounds)

        let imgR = imageRect
        let extR = extendedRect
        guard imgR.width > 0, imgR.height > 0 else { return }

        // チェッカーボード（拡張領域のみ）
        drawCheckerboard(in: extR, excluding: imgR, ctx: ctx)

        // 元画像描画
        if let cgImage = cachedCGImage {
            ctx.draw(cgImage, in: imgR)
        }

        // 元画像境界を点線
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(imgR)
        ctx.restoreGState()

        // 拡張領域の外枠
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(extR)

        // ハンドル
        let handleRadius: CGFloat = 6
        for p in handlePoints(for: extR) {
            let rect = CGRect(x: p.x - handleRadius, y: p.y - handleRadius,
                              width: handleRadius * 2, height: handleRadius * 2)
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func drawCheckerboard(in extRect: CGRect, excluding imgRect: CGRect, ctx: CGContext) {
        let tileSize: CGFloat = 10
        let light = NSColor(white: 0.85, alpha: 1).cgColor
        let dark = NSColor(white: 0.70, alpha: 1).cgColor

        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(extRect)
        path.addRect(imgRect)
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)

        let startCol = Int(floor(extRect.minX / tileSize))
        let endCol = Int(ceil(extRect.maxX / tileSize))
        let startRow = Int(floor(extRect.minY / tileSize))
        let endRow = Int(ceil(extRect.maxY / tileSize))

        for row in startRow ..< endRow {
            for col in startCol ..< endCol {
                ctx.setFillColor((row + col) % 2 == 0 ? light : dark)
                let tileRect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize,
                                      width: tileSize, height: tileSize)
                    .intersection(extRect)
                if !tileRect.isEmpty {
                    ctx.fill(tileRect)
                }
            }
        }
        ctx.restoreGState()
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let extR = extendedRect
        let hitRadius: CGFloat = 10

        var hit: HandleIndex?
        for (i, p) in handlePoints(for: extR).enumerated() {
            let dx = vp.x - p.x
            let dy = vp.y - p.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                hit = HandleIndex(rawValue: i)
                break
            }
        }

        if let h = hit {
            dragKind = .handle(h)
            dragStartViewPoint = vp
            dragStartInsets = insets
        } else {
            dragKind = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if case .none = dragKind { return }
        performDrag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        if case .none = dragKind { return }
        performDrag(to: convert(event.locationInWindow, from: nil))
        dragKind = .none
        coordinator?.commitInsets(insets)
    }

    private func performDrag(to vp: CGPoint) {
        guard case .handle(let h) = dragKind else { return }

        let scale = viewScale()
        guard scale > 0 else { return }

        let dxView = vp.x - dragStartViewPoint.x
        let dyView = vp.y - dragStartViewPoint.y
        let dxPx = dxView / scale
        let dyPx = dyView / scale

        var newInsets = dragStartInsets

        switch h {
        case .top:
            newInsets.top = clampInset(dragStartInsets.top + dyPx)
        case .bottom:
            newInsets.bottom = clampInset(dragStartInsets.bottom - dyPx)
        case .left:
            newInsets.left = clampInset(dragStartInsets.left - dxPx)
        case .right:
            newInsets.right = clampInset(dragStartInsets.right + dxPx)
        case .topLeft:
            newInsets.top = clampInset(dragStartInsets.top + dyPx)
            newInsets.left = clampInset(dragStartInsets.left - dxPx)
        case .topRight:
            newInsets.top = clampInset(dragStartInsets.top + dyPx)
            newInsets.right = clampInset(dragStartInsets.right + dxPx)
        case .bottomLeft:
            newInsets.bottom = clampInset(dragStartInsets.bottom - dyPx)
            newInsets.left = clampInset(dragStartInsets.left - dxPx)
        case .bottomRight:
            newInsets.bottom = clampInset(dragStartInsets.bottom - dyPx)
            newInsets.right = clampInset(dragStartInsets.right + dxPx)
        }

        insets = newInsets
        coordinator?.commitInsets(insets)
        needsDisplay = true
    }

    private func clampInset(_ value: CGFloat) -> CGFloat {
        min(maxExpandPx, max(0, round(value)))
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
