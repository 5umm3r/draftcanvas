import SwiftUI
import AppKit

// MARK: - NSViewRepresentable

struct CropCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var cropRect: CGRect
    var template: AspectTemplate
    var onSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> CropCanvasNSView {
        let view = CropCanvasNSView(image: image, cropRect: cropRect, template: template)
        view.coordinator = context.coordinator
        context.coordinator.canvasView = view
        return view
    }

    func updateNSView(_ nsView: CropCanvasNSView, context: Context) {
        context.coordinator.parent = self
        // Template が変わった場合はリセット（中央配置の最大内接矩形）
        if nsView.template != template {
            nsView.template = template
            nsView.applyTemplate()
        } else {
            nsView.cropRect = cropRect
        }
        nsView.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: CropCanvasView
        weak var canvasView: CropCanvasNSView?

        init(parent: CropCanvasView) { self.parent = parent }

        @MainActor
        func commitCropRect(_ rect: CGRect) {
            parent.cropRect = rect
            parent.onSizeChange(rect.size)
        }

        @MainActor
        func reportSize(_ size: CGSize) {
            parent.onSizeChange(size)
        }
    }
}
