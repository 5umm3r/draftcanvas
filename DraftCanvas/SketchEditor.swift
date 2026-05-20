import SwiftUI
import AppKit

// MARK: - Sheet

struct SketchEditorSheet: View {
    let canvasPixelSize: CGSize
    let onComplete: ([SketchStroke]) -> Void
    let onCancel: () -> Void

    @State private var strokes: [SketchStroke]
    @State private var undoneStrokes: [SketchStroke] = []
    @State private var brushRadius: CGFloat = 20
    @State private var isEraser: Bool = false
    @State private var selectedColor: CodableColor = .black
    @State private var isConfirmingClear: Bool = false

    init(
        canvasPixelSize: CGSize,
        initialStrokes: [SketchStroke] = [],
        onComplete: @escaping ([SketchStroke]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.canvasPixelSize = canvasPixelSize
        self._strokes = State(initialValue: initialStrokes)
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            SketchCanvasView(
                canvasPixelSize: canvasPixelSize,
                strokes: $strokes,
                brushRadius: brushRadius,
                isEraser: isEraser,
                selectedColor: selectedColor,
                onStrokeCommit: { undoneStrokes = [] }
            )
        }
        .frame(minWidth: 800, minHeight: 620)
        .confirmationDialog("描画をすべて消去しますか？", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("消去", role: .destructive) {
                strokes = []
                undoneStrokes = []
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onKeyPress(.init("[")) { brushRadius = max(5, brushRadius - 5); return .handled }
        .onKeyPress(.init("]")) { brushRadius = min(80, brushRadius + 5); return .handled }
        .onKeyPress(.init("e")) { isEraser.toggle(); return .handled }
        .onKeyPress(.init("1")) { selectPreset(0); return .handled }
        .onKeyPress(.init("2")) { selectPreset(1); return .handled }
        .onKeyPress(.init("3")) { selectPreset(2); return .handled }
        .onKeyPress(.init("4")) { selectPreset(3); return .handled }
        .onKeyPress(.init("5")) { selectPreset(4); return .handled }
    }

    private func selectPreset(_ index: Int) {
        let presets = CodableColor.presets
        guard index < presets.count else { return }
        selectedColor = presets[index]
        isEraser = false
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // ブラシ径
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $brushRadius, in: 5 ... 80, step: 1)
                .frame(width: 100)
            Text("\(Int(brushRadius))px")
                .font(.caption.monospacedDigit())
                .frame(width: 36)

            Divider().frame(height: 20)

            // カラーパレット
            HStack(spacing: 4) {
                ForEach(0..<CodableColor.presets.count, id: \.self) { i in
                    let color = CodableColor.presets[i]
                    let isSelected = !isEraser && selectedColor == color
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                        )
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                        .onTapGesture {
                            selectedColor = color
                            isEraser = false
                        }
                }
            }

            Divider().frame(height: 20)

            // 消しゴム
            Toggle(isOn: $isEraser) {
                Image(systemName: "eraser")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)

            Divider().frame(height: 20)

            // Undo / Redo
            HStack(spacing: 4) {
                Button {
                    guard let last = strokes.last else { return }
                    undoneStrokes.append(last)
                    strokes.removeLast()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    guard let last = undoneStrokes.last else { return }
                    strokes.append(last)
                    undoneStrokes.removeLast()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(undoneStrokes.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            // Clear
            Button {
                isConfirmingClear = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(strokes.isEmpty)

            Spacer()

            Button("キャンセル", role: .cancel) { onCancel() }
                .fixedSize()
                .keyboardShortcut(.escape, modifiers: [])

            Button("完了") { onComplete(strokes) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - NSViewRepresentable

struct SketchCanvasView: NSViewRepresentable {
    let canvasPixelSize: CGSize
    @Binding var strokes: [SketchStroke]
    var brushRadius: CGFloat
    var isEraser: Bool
    var selectedColor: CodableColor
    var onStrokeCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SketchCanvasNSView {
        let view = SketchCanvasNSView(canvasPixelSize: canvasPixelSize)
        view.coordinator = context.coordinator
        context.coordinator.canvasView = view
        return view
    }

    func updateNSView(_ nsView: SketchCanvasNSView, context: Context) {
        context.coordinator.parent = self
        nsView.brushRadius = brushRadius
        nsView.isEraser = isEraser
        nsView.selectedColor = selectedColor
        nsView.syncStrokes(strokes)
        nsView.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: SketchCanvasView
        weak var canvasView: SketchCanvasNSView?

        init(parent: SketchCanvasView) { self.parent = parent }

        @MainActor
        func commitStroke(_ stroke: SketchStroke) {
            parent.strokes.append(stroke)
            parent.onStrokeCommit()
        }
    }
}

// MARK: - NSView

final class SketchCanvasNSView: NSView {
    let canvasPixelSize: CGSize
    var brushRadius: CGFloat = 20
    var isEraser: Bool = false
    var selectedColor: CodableColor = .black
    weak var coordinator: SketchCanvasView.Coordinator?

    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var currentPoints: [CGPoint] = []
    private var cursorPoint: CGPoint? = nil

    // Persistent RGBA buffer (white background)
    private var sketchBuffer: CGContext?
    private var committedStrokeCount: Int = 0
    private var cachedCGImage: CGImage?

    init(canvasPixelSize: CGSize) {
        self.canvasPixelSize = canvasPixelSize
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

    // MARK: - Stroke sync

    func syncStrokes(_ newStrokes: [SketchStroke]) {
        if committedStrokeCount == 0 && !newStrokes.isEmpty {
            rebuildBuffer(from: newStrokes)
        } else if newStrokes.count < committedStrokeCount {
            rebuildBuffer(from: newStrokes)
        }
        committedStrokeCount = newStrokes.count
    }

    // MARK: - Buffer management

    private func ensureBuffer() {
        let size = canvasPixelSize
        guard size.width > 0, size.height > 0 else { return }
        guard sketchBuffer == nil else { return }

        sketchBuffer = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        clearBuffer()
    }

    private func clearBuffer() {
        guard let ctx = sketchBuffer else { return }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: canvasPixelSize))
        cachedCGImage = nil
    }

    private func rebuildBuffer(from strokes: [SketchStroke]) {
        ensureBuffer()
        clearBuffer()
        for stroke in strokes {
            writeStrokeToBuffer(points: stroke.points, radius: stroke.radius, color: stroke.color, isEraser: stroke.isEraser)
        }
    }

    private func writeStrokeToBuffer(points: [CGPoint], radius: CGFloat, color: CodableColor, isEraser: Bool) {
        ensureBuffer()
        guard let ctx = sketchBuffer, !points.isEmpty else { return }

        let fillColor = isEraser
            ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            : color.cgColor
        ctx.setFillColor(fillColor)

        let h = canvasPixelSize.height
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
        cachedCGImage = nil
    }

    // MARK: - Coordinate helpers

    private var canvasRect: CGRect {
        guard canvasPixelSize.width > 0, canvasPixelSize.height > 0 else { return .zero }
        let boundsSize = bounds.size
        let scale = min(boundsSize.width / canvasPixelSize.width, boundsSize.height / canvasPixelSize.height) * zoom
        let drawW = canvasPixelSize.width * scale
        let drawH = canvasPixelSize.height * scale
        let x = (boundsSize.width - drawW) / 2 + panOffset.x
        let y = (boundsSize.height - drawH) / 2 + panOffset.y
        return CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    private func toCanvasPoint(_ vp: CGPoint) -> CGPoint {
        let r = canvasRect
        guard r.width > 0, r.height > 0 else { return .zero }
        let px = (vp.x - r.minX) / r.width * canvasPixelSize.width
        let py = (1 - (vp.y - r.minY) / r.height) * canvasPixelSize.height
        return CGPoint(x: px, y: py)
    }

    private func viewBrushRect(around vp: CGPoint) -> NSRect {
        let r = canvasRect
        let viewR = brushRadius / max(1, canvasPixelSize.width) * r.width + 8
        return CGRect(x: vp.x - viewR, y: vp.y - viewR, width: viewR * 2, height: viewR * 2)
            .intersection(bounds)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // チェッカーボード背景（キャンバス外）
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

        let r = canvasRect
        guard r.width > 0, r.height > 0 else { return }

        // スケッチバッファを描画
        ensureBuffer()
        if let bufCtx = sketchBuffer {
            if cachedCGImage == nil { cachedCGImage = bufCtx.makeImage() }
        }
        if let img = cachedCGImage {
            ctx.draw(img, in: r)
        } else {
            // バッファ未初期化時は白塗り
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(r)
        }

        // カーソル
        if let cp = cursorPoint {
            let viewR = brushRadius / max(1, canvasPixelSize.width) * r.width
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
        let cp = toCanvasPoint(vp)
        currentPoints = [cp]
        writeStrokeToBuffer(points: [cp], radius: brushRadius, color: selectedColor, isEraser: isEraser)
        cursorPoint = vp
        setNeedsDisplay(viewBrushRect(around: vp))
    }

    override func mouseDragged(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let cp = toCanvasPoint(vp)
        if let last = currentPoints.last {
            writeStrokeToBuffer(points: [last, cp], radius: brushRadius, color: selectedColor, isEraser: isEraser)
        }
        currentPoints.append(cp)
        let prevCursor = cursorPoint
        cursorPoint = vp

        var dirty = viewBrushRect(around: vp)
        if let prev = prevCursor { dirty = dirty.union(viewBrushRect(around: prev)) }
        setNeedsDisplay(dirty)
    }

    override func mouseUp(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        if !currentPoints.isEmpty {
            currentPoints.append(toCanvasPoint(vp))
            let stroke = SketchStroke(points: currentPoints, radius: brushRadius, color: selectedColor, isEraser: isEraser)
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

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        needsDisplay = true
    }
}
