import SwiftUI
import AppKit

// MARK: - NSViewRepresentable

struct MaskCanvasView: NSViewRepresentable {
    let originalImage: NSImage
    @Binding var strokes: [MaskStroke]
    var brushRadius: CGFloat
    var isEraser: Bool
    var onStrokeCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MaskCanvasNSView {
        let view = MaskCanvasNSView(image: originalImage)
        view.coordinator = context.coordinator
        context.coordinator.canvasView = view
        return view
    }

    func updateNSView(_ nsView: MaskCanvasNSView, context: Context) {
        context.coordinator.parent = self
        var changed = false
        if nsView.brushRadius != brushRadius {
            nsView.brushRadius = brushRadius
            changed = true
        }
        if nsView.isEraser != isEraser {
            nsView.isEraser = isEraser
            changed = true
        }
        if nsView.syncStrokes(strokes) { changed = true }
        if changed { nsView.needsDisplay = true }
    }

    final class Coordinator: NSObject {
        var parent: MaskCanvasView
        weak var canvasView: MaskCanvasNSView?

        init(parent: MaskCanvasView) { self.parent = parent }

        @MainActor
        func commitStroke(_ stroke: MaskStroke) {
            parent.strokes.append(stroke)
            parent.onStrokeCommit()
        }
    }
}
