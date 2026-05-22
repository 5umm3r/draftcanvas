import SwiftUI
import AppKit

extension View {
    func rightClickPopover<Content: View>(
        onOpen: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(RightClickPopoverBridge(onOpen: onOpen, popoverContent: content))
    }
}

private struct RightClickPopoverBridge<Content: View>: NSViewRepresentable {
    let onOpen: () -> Void
    let popoverContent: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HandlerView {
        let v = HandlerView()
        v.onTriggered = { [weak v] in
            guard let v else { return }
            context.coordinator.show(from: v, content: popoverContent, onOpen: onOpen)
        }
        return v
    }

    func updateNSView(_ nsView: HandlerView, context: Context) {
        nsView.onTriggered = { [weak nsView] in
            guard let nsView else { return }
            context.coordinator.show(from: nsView, content: popoverContent, onOpen: onOpen)
        }
    }

    @MainActor
    class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?

        func show(from view: NSView, content: () -> Content, onOpen: () -> Void) {
            if let p = popover, p.isShown { p.close(); return }
            onOpen()
            let p = NSPopover()
            p.animates = false
            p.behavior = .transient
            p.contentViewController = NSHostingController(rootView: content())
            p.delegate = self
            popover = p
            p.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
        }

        func popoverDidClose(_ notification: Notification) { popover = nil }
    }

    class HandlerView: NSView {
        var onTriggered: (@MainActor () -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated { onTriggered?() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }
    }
}
