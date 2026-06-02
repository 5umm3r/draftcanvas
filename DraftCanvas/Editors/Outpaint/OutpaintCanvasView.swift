import SwiftUI
import AppKit

struct OutpaintCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var insets: OutpaintInsets

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> OutpaintCanvasNSView {
        let view = OutpaintCanvasNSView(image: image)
        view.coordinator = context.coordinator
        context.coordinator.canvasView = view
        return view
    }

    func updateNSView(_ nsView: OutpaintCanvasNSView, context: Context) {
        context.coordinator.parent = self
        nsView.insets = insets
        nsView.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: OutpaintCanvasView
        weak var canvasView: OutpaintCanvasNSView?

        init(parent: OutpaintCanvasView) { self.parent = parent }

        @MainActor
        func commitInsets(_ newInsets: OutpaintInsets) {
            parent.insets = newInsets
        }
    }
}
