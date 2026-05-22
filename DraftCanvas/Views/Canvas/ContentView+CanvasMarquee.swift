import SwiftUI
import AppKit

extension ContentView {
    func handleMarqueeDrag(value: DragGesture.Value) {
        guard !viewModel.projects.isEmpty && !canvasEntries.isEmpty else { return }
        if !isDraggingMarquee {
            let isOnCard = cardFrames.values.contains { $0.contains(value.startLocation) }
            if isOnCard {
                isDragStartedOnCard = true
                return
            }
            isDragStartedOnCard = false
            isDraggingMarquee = true
            viewModel.isSelectionMode = true
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            marqueeAdditive = flags.contains(.shift) || flags.contains(.command)
            dragSelectedIDs = marqueeAdditive ? viewModel.selectedItemIDs : []
        }
        guard !isDragStartedOnCard else { return }
        let s = value.startLocation
        let c = value.location
        let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(s.x - c.x), height: abs(s.y - c.y))
        marqueeRect = rect
        let hits = Set(cardFrames.compactMap { id, frame in frame.intersects(rect) ? id : nil })
        dragSelectedIDs = dragSelectedIDs.union(hits)
        viewModel.selectedItemIDs = dragSelectedIDs
        canvasAutoScroller.updateVelocity(mouseY: c.y, viewHeight: canvasViewportHeight)
        if canvasAutoScroller.velocity != 0 { canvasAutoScroller.start() } else { canvasAutoScroller.stop() }
    }

    func handleMarqueeEnd(value: DragGesture.Value) {
        canvasAutoScroller.stop()
        marqueeRect = nil
        isDraggingMarquee = false
        isDragStartedOnCard = false
        dragSelectedIDs = []
    }
}
