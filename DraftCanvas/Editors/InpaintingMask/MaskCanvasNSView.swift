import AppKit

// MARK: - NSView

final class MaskCanvasNSView: NSView {
    var image: NSImage
    var brushRadius: CGFloat = 20
    var isEraser: Bool = false
    weak var coordinator: MaskCanvasView.Coordinator?

    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var currentPoints: [CGPoint] = []
    private var cursorPoint: CGPoint? = nil

    // Persistent grayscale mask buffer: white = masked, black = not masked
    private var maskBuffer: CGContext?
    private var maskBufferPixelSize: CGSize = .zero
    private var committedStrokeCount: Int = 0
    private var cachedCGImage: CGImage?
    private var cachedMaskCGImage: CGImage?

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

    // MARK: - Stroke sync (called from updateNSView)

    @discardableResult
    func syncStrokes(_ newStrokes: [MaskStroke]) -> Bool {
        var rebuilt = false
        if committedStrokeCount == 0 && !newStrokes.isEmpty {
            rebuildMaskBuffer(from: newStrokes)
            rebuilt = true
        } else if newStrokes.count < committedStrokeCount {
            rebuildMaskBuffer(from: newStrokes)
            rebuilt = true
        }
        committedStrokeCount = newStrokes.count
        return rebuilt
    }

    // MARK: - Buffer management

    private func imagePixelSize() -> CGSize {
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let ph = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            if pw > 0, ph > 0 { return CGSize(width: pw, height: ph) }
        }
        return image.size
    }

    private func ensureMaskBuffer() {
        let size = imagePixelSize()
        guard size.width > 0, size.height > 0 else { return }
        guard maskBuffer == nil || maskBufferPixelSize != size else { return }

        maskBufferPixelSize = size
        maskBuffer = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        clearBuffer()
    }

    private func clearBuffer() {
        guard let ctx = maskBuffer else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: maskBufferPixelSize))
        cachedMaskCGImage = nil
    }

    private func rebuildMaskBuffer(from strokes: [MaskStroke]) {
        ensureMaskBuffer()
        clearBuffer()
        for stroke in strokes {
            writeStrokeToBuffer(points: stroke.points, radius: stroke.radius, isEraser: stroke.isEraser)
        }
    }

    // Write brush circles directly to the gray buffer (incremental, O(new points only))
    private func writeStrokeToBuffer(points: [CGPoint], radius: CGFloat, isEraser: Bool) {
        ensureMaskBuffer()
        guard let ctx = maskBuffer, !points.isEmpty else { return }

        let gray: CGFloat = isEraser ? 0 : 1
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))

        let h = maskBufferPixelSize.height
        let r = max(1, radius)

        if points.count == 1 {
            let p = CGPoint(x: points[0].x, y: h - points[0].y)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        } else {
            for i in 1 ..< points.count {
                let p0 = CGPoint(x: points[i - 1].x, y: h - points[i - 1].y)
                let p1 = CGPoint(x: points[i].x, y: h - points[i].y)
                let dist = hypot(p1.x - p0.x, p1.y - p0.y)
                let steps = max(1, Int(dist / (r * 0.5)))
                for s in 0 ... steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let x = p0.x + (p1.x - p0.x) * t
                    let y = p0.y + (p1.y - p0.y) * t
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }
        }
        cachedMaskCGImage = nil
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

    // NSView point (y=0 at bottom) → image pixel coord (y=0 at top)
    private func toImagePoint(_ vp: CGPoint) -> CGPoint {
        let r = imageRect
        guard r.width > 0, r.height > 0 else { return .zero }
        let imgSize = imagePixelSize()
        let px = (vp.x - r.minX) / r.width * imgSize.width
        let py = (1 - (vp.y - r.minY) / r.height) * imgSize.height
        return CGPoint(x: px, y: py)
    }

    // View-space rect covering the brush cursor area
    private func viewBrushRect(around vp: CGPoint) -> NSRect {
        let r = imageRect
        let viewR = brushRadius / max(1, imagePixelSize().width) * r.width + 8
        return CGRect(x: vp.x - viewR, y: vp.y - viewR, width: viewR * 2, height: viewR * 2)
            .intersection(bounds)
    }

    // MARK: - Drawing (O(1) per frame)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        EditorCheckerboard.fill(bounds, in: ctx)

        let r = imageRect
        guard r.width > 0, r.height > 0 else { return }

        // Original image
        if let cgImage = cachedCGImage {
            ctx.draw(cgImage, in: r)
        }

        // Mask overlay: clip to white areas of buffer, fill red
        ensureMaskBuffer()
        if let bufCtx = maskBuffer {
            if cachedMaskCGImage == nil { cachedMaskCGImage = bufCtx.makeImage() }
        }
        if let maskImage = cachedMaskCGImage {
            ctx.saveGState()
            ctx.setAlpha(0.5)
            ctx.clip(to: r, mask: maskImage)
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(r)
            ctx.restoreGState()
        }

        // Cursor circle
        if let cp = cursorPoint {
            let viewR = brushRadius / max(1, imagePixelSize().width) * r.width
            let circle = CGRect(x: cp.x - viewR, y: cp.y - viewR, width: viewR * 2, height: viewR * 2)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: circle)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: circle)
        }
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let ip = toImagePoint(vp)
        currentPoints = [ip]
        writeStrokeToBuffer(points: [ip], radius: brushRadius, isEraser: isEraser)
        cursorPoint = vp
        setNeedsDisplay(viewBrushRect(around: vp))
    }

    override func mouseDragged(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let ip = toImagePoint(vp)
        if let last = currentPoints.last {
            writeStrokeToBuffer(points: [last, ip], radius: brushRadius, isEraser: isEraser)
        }
        currentPoints.append(ip)
        let prevCursor = cursorPoint
        cursorPoint = vp

        // Invalidate union of old cursor and new brush area
        var dirty = viewBrushRect(around: vp)
        if let prev = prevCursor { dirty = dirty.union(viewBrushRect(around: prev)) }
        setNeedsDisplay(dirty)
    }

    override func mouseUp(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        if !currentPoints.isEmpty {
            currentPoints.append(toImagePoint(vp))
            let stroke = MaskStroke(points: currentPoints, radius: brushRadius, isEraser: isEraser)
            committedStrokeCount += 1
            coordinator?.commitStroke(stroke)
        }
        currentPoints = []
        cursorPoint = vp
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        var dirty = viewBrushRect(around: vp)
        if let prev = cursorPoint { dirty = dirty.union(viewBrushRect(around: prev)) }
        cursorPoint = vp
        setNeedsDisplay(dirty)
    }

    override func mouseExited(with event: NSEvent) {
        if let prev = cursorPoint { setNeedsDisplay(viewBrushRect(around: prev)) }
        cursorPoint = nil
    }

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

    // MARK: - Scroll (pan)

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        needsDisplay = true
    }
}
