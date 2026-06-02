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
        var changed = false
        if nsView.brushRadius != brushRadius {
            nsView.brushRadius = brushRadius
            changed = true
        }
        if nsView.isEraser != isEraser {
            nsView.isEraser = isEraser
            changed = true
        }
        if nsView.selectedColor != selectedColor {
            nsView.selectedColor = selectedColor
            changed = true
        }
        if nsView.syncStrokes(strokes) { changed = true }
        if changed { nsView.needsDisplay = true }
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
