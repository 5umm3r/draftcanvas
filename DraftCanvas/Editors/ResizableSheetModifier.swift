import SwiftUI
import AppKit

struct ResizableSheet: ViewModifier {
    let minSize: CGSize

    func body(content: Content) -> some View {
        content
            .background(
                SheetWindowAccessor(minSize: minSize)
            )
    }
}

private struct SheetWindowAccessor: NSViewRepresentable {
    let minSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: minSize.width, height: minSize.height)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func resizableSheet(minWidth: CGFloat = 800, minHeight: CGFloat = 620) -> some View {
        modifier(ResizableSheet(minSize: CGSize(width: minWidth, height: minHeight)))
    }
}
