import SwiftUI
import AppKit

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
