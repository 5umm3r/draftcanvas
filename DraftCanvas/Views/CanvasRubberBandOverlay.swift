import SwiftUI
import AppKit

struct CanvasRubberBandOverlay: NSViewRepresentable {
    let cardFrames: [UUID: CGRect]
    let isEnabled: Bool
    @Binding var marqueeRect: CGRect?
    let autoScroller: CanvasAutoScroller
    let onMarqueeBegan: () -> Void
    let onMarqueeChanged: (CGRect, Bool) -> Void
    let onMarqueeEnded: (CGRect, Bool) -> Void

    func makeNSView(context: Context) -> RubberBandHostView {
        let view = RubberBandHostView()
        view.coordinator = context.coordinator
        view.autoScroller = autoScroller
        autoScroller.hostView = view
        return view
    }

    func updateNSView(_ nsView: RubberBandHostView, context: Context) {
        nsView.cardFrames = cardFrames
        nsView.isEnabled = isEnabled
        nsView.autoScroller = autoScroller
        autoScroller.hostView = nsView
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator {
        var parent: CanvasRubberBandOverlay

        init(parent: CanvasRubberBandOverlay) {
            self.parent = parent
        }

        func setMarqueeRect(_ rect: CGRect?) {
            parent.marqueeRect = rect
        }

        func marqueeBegan() {
            parent.onMarqueeBegan()
        }

        func marqueeChanged(_ rect: CGRect, additive: Bool) {
            parent.onMarqueeChanged(rect, additive)
        }

        func marqueeEnded(_ rect: CGRect, additive: Bool) {
            parent.onMarqueeEnded(rect, additive)
        }
    }
}

final class RubberBandHostView: NSView {
    var cardFrames: [UUID: CGRect] = [:]
    var isEnabled: Bool = true
    weak var coordinator: CanvasRubberBandOverlay.Coordinator?
    var autoScroller: CanvasAutoScroller?

    private var dragStart: CGPoint?
    private var additive: Bool = false
    private var dragBegan: Bool = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        let localPoint = convert(point, from: superview)
        for (_, rect) in cardFrames where rect.contains(localPoint) {
            return nil
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let loc = convert(event.locationInWindow, from: nil)
        dragStart = loc
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        additive = flags.contains(.shift) || flags.contains(.command)
        dragBegan = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dist = hypot(current.x - start.x, current.y - start.y)
        guard dist >= 4 else { return }
        let didBegin = !dragBegan
        if didBegin { dragBegan = true }
        let rect = makeRect(from: start, to: current)
        let isAdditive = additive
        let c = coordinator
        let scroller = autoScroller
        let h = bounds.height
        Task { @MainActor in
            if didBegin { c?.marqueeBegan() }
            c?.setMarqueeRect(rect)
            c?.marqueeChanged(rect, additive: isAdditive)
            scroller?.updateVelocity(mouseY: current.y, viewHeight: h)
            if (scroller?.velocity ?? 0) != 0 {
                scroller?.start()
            } else {
                scroller?.stop()
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let scroller = autoScroller
        let c = coordinator
        let start = dragStart
        let began = dragBegan
        let isAdditive = additive
        dragStart = nil
        dragBegan = false
        Task { @MainActor in
            scroller?.stop()
            guard let start, began else { return }
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                              width: abs(start.x - current.x), height: abs(start.y - current.y))
            c?.marqueeEnded(rect, additive: isAdditive)
            c?.setMarqueeRect(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, dragStart != nil {
            let scroller = autoScroller
            let c = coordinator
            dragStart = nil
            dragBegan = false
            Task { @MainActor in
                scroller?.stop()
                c?.setMarqueeRect(nil)
            }
        } else {
            super.keyDown(with: event)
        }
    }

    private func makeRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
