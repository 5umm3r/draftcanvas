import SwiftUI
import AppKit

struct AutoScrollerAnchor: NSViewRepresentable {
    let scroller: CanvasAutoScroller

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        scroller.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scroller.hostView = nsView
    }
}
