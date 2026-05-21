import SwiftUI
import AppKit

// MARK: - EditMode

enum EditMode: String, CaseIterable {
    case select = "選択"
    case addRect = "追加"
}

struct MaterialExtractionPreview: Identifiable {
    let id = UUID()
    let item: ProjectItem
    let session: MaterialExtractor.ExtractionSession
}

struct MaterialExtractionSheet: View {
    let preview: MaterialExtractionPreview
    @ObservedObject var viewModel: DraftCanvasViewModel

    @State private var selectedInstanceIDs: Set<UUID> = []
    @State private var editedInstances: [MaterialExtractor.DetectedInstance] = []
    @State private var isSaving: Bool = false
    @State private var editMode: EditMode = .select
    @State private var removeBackground: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            MaterialOverlayCanvasView(
                session: preview.session,
                instances: editedInstances,
                selectedInstanceIDs: $selectedInstanceIDs,
                editMode: editMode,
                onAddInstance: { inst in
                    editedInstances.append(inst)
                    selectedInstanceIDs.insert(inst.id)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
            controlBar
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 800, minHeight: 620)
        .onAppear {
            editedInstances = preview.session.instances
            selectedInstanceIDs = Set(editedInstances.map(\.id))
        }
        .onDisappear {
            isSaving = false
        }
        .onChange(of: viewModel.errorToast) { _, newValue in
            if newValue != nil { isSaving = false }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedInstanceIDs.count) / \(editedInstances.count) 個選択")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("すべて選択") {
                selectedInstanceIDs = Set(editedInstances.map(\.id))
            }
            .controlSize(.small)

            Button("すべて解除") {
                selectedInstanceIDs.removeAll()
            }
            .controlSize(.small)

            Picker("モード", selection: $editMode) {
                ForEach(EditMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)

            Spacer()

            Toggle("背景除去", isOn: $removeBackground)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button("キャンセル") {
                viewModel.cancelMaterialExtraction()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button(isSaving ? LocalizedStringKey("保存中...") : LocalizedStringKey("保存 (\(selectedInstanceIDs.count))")) {
                isSaving = true
                viewModel.commitMaterialExtraction(
                    originalItem: preview.item,
                    session: preview.session,
                    instances: editedInstances,
                    selectedInstanceIDs: selectedInstanceIDs,
                    removeBackground: removeBackground
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedInstanceIDs.isEmpty || isSaving)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }
}

// MARK: - NSViewRepresentable

struct MaterialOverlayCanvasView: NSViewRepresentable {
    let session: MaterialExtractor.ExtractionSession
    var instances: [MaterialExtractor.DetectedInstance]
    @Binding var selectedInstanceIDs: Set<UUID>
    var editMode: EditMode
    var onAddInstance: ((MaterialExtractor.DetectedInstance) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MaterialOverlayNSView {
        let view = MaterialOverlayNSView(session: session)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MaterialOverlayNSView, context: Context) {
        context.coordinator.parent = self
        nsView.instances = instances
        nsView.selectedInstanceIDs = selectedInstanceIDs
        nsView.editMode = editMode
        nsView.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: MaterialOverlayCanvasView

        init(parent: MaterialOverlayCanvasView) { self.parent = parent }

        @MainActor
        func toggle(_ id: UUID) {
            if parent.selectedInstanceIDs.contains(id) {
                parent.selectedInstanceIDs.remove(id)
            } else {
                parent.selectedInstanceIDs.insert(id)
            }
        }

        @MainActor
        func addUserInstance(imageBBox: CGRect) {
            let inst = MaterialExtractor.makeUserInstance(
                imageBBox: imageBBox,
                imagePixelSize: parent.session.imagePixelSize,
                extent: parent.session.extent
            )
            parent.onAddInstance?(inst)
        }
    }
}

// MARK: - NSView

final class MaterialOverlayNSView: NSView {
    let session: MaterialExtractor.ExtractionSession
    var instances: [MaterialExtractor.DetectedInstance] = []
    var selectedInstanceIDs: Set<UUID> = []
    weak var coordinator: MaterialOverlayCanvasView.Coordinator?
    var editMode: EditMode = .select

    private var dragOrigin: CGPoint? = nil
    private var currentDragRect: CGRect? = nil

    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero

    private static let palette: [NSColor] = [
        .systemRed, .systemBlue, .systemGreen, .systemOrange,
        .systemPurple, .systemTeal, .systemPink, .systemIndigo, .systemYellow
    ]

    init(session: MaterialExtractor.ExtractionSession) {
        self.session = session
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

    /// NSView 座標内で画像が描画される矩形（zoom/pan 考慮）
    private var imageRect: CGRect {
        let imgSize = session.imagePixelSize
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }
        let boundsSize = bounds.size
        let scale = min(boundsSize.width / imgSize.width, boundsSize.height / imgSize.height) * zoom
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let x = (boundsSize.width - drawW) / 2 + panOffset.x
        let y = (boundsSize.height - drawH) / 2 + panOffset.y
        return CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    /// NSView 座標（y=0下）→ CIImage ピクセル座標（y=0下, 左下原点）
    private func toCIImagePoint(_ vp: CGPoint) -> CGPoint {
        let r = imageRect
        guard r.width > 0, r.height > 0 else { return .zero }
        let s = session.imagePixelSize
        return CGPoint(
            x: (vp.x - r.minX) / r.width  * s.width,
            y: (vp.y - r.minY) / r.height * s.height
        )
    }

    /// imageBoundingBox（CIImage座標, y=0下）→ NSView 座標 CGRect
    private func viewRect(for bbox: CGRect) -> CGRect {
        let r = imageRect
        let s = session.imagePixelSize
        guard r.width > 0, s.width > 0 else { return .zero }
        return CGRect(
            x: r.minX + bbox.minX / s.width  * r.width,
            y: r.minY + bbox.minY / s.height * r.height,
            width:  bbox.width  / s.width  * r.width,
            height: bbox.height / s.height * r.height
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(bounds)

        let r = imageRect
        guard r.width > 0, r.height > 0 else { return }

        ctx.draw(session.originalCG, in: r)

        for (i, inst) in instances.enumerated() {
            let isSelected = selectedInstanceIDs.contains(inst.id)
            let color = Self.palette[i % Self.palette.count]
            let vr = viewRect(for: inst.imageBoundingBox)

            // 選択状態: 塗りつぶし tint + 太枠線 / 未選択: 細枠線のみ
            if isSelected {
                ctx.saveGState()
                ctx.setAlpha(0.18)
                ctx.setFillColor(color.cgColor)
                ctx.fill(vr)
                ctx.restoreGState()
            }

            ctx.saveGState()
            ctx.setStrokeColor((isSelected ? color : NSColor.gray).cgColor)
            ctx.setLineWidth(isSelected ? 2.0 : 0.5)
            ctx.setAlpha(isSelected ? 1.0 : 0.35)
            ctx.stroke(vr)
            ctx.restoreGState()
        }

        // 矩形追加モード: ドラッグ中の破線プレビュー
        if editMode == .addRect, let dragRect = currentDragRect {
            let vr = viewRect(for: dragRect)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.stroke(vr)
            ctx.restoreGState()
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        let ciPt = toCIImagePoint(vp)
        switch editMode {
        case .select:
            if let hit = pickInstance(at: ciPt) {
                coordinator?.toggle(hit.id)
                needsDisplay = true
            }
        case .addRect:
            dragOrigin = ciPt
            currentDragRect = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if editMode == .addRect, let origin = dragOrigin {
            let vp = convert(event.locationInWindow, from: nil)
            var ciPt = toCIImagePoint(vp)
            // 画像ピクセル範囲にクランプ
            let s = session.imagePixelSize
            ciPt.x = max(0, min(s.width, ciPt.x))
            ciPt.y = max(0, min(s.height, ciPt.y))
            let minX = min(origin.x, ciPt.x)
            let minY = min(origin.y, ciPt.y)
            let maxX = max(origin.x, ciPt.x)
            let maxY = max(origin.y, ciPt.y)
            currentDragRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if editMode == .addRect {
            guard let rect = currentDragRect, rect.width > 5, rect.height > 5 else {
                dragOrigin = nil
                currentDragRect = nil
                return
            }
            coordinator?.addUserInstance(imageBBox: rect)
            dragOrigin = nil
            currentDragRect = nil
            needsDisplay = true
        }
    }

    /// hit-test: imageBoundingBox（CIImage座標）でヒットしたインスタンスのうち面積最小を返す
    private func pickInstance(at ciPt: CGPoint) -> MaterialExtractor.DetectedInstance? {
        let hits = instances.filter { $0.imageBoundingBox.contains(ciPt) }
        return hits.min(by: {
            $0.imageBoundingBox.width * $0.imageBoundingBox.height
            < $1.imageBoundingBox.width * $1.imageBoundingBox.height
        })
    }

    // MARK: - Scroll (pan)

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        needsDisplay = true
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
}
