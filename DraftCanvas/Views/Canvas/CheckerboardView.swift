import SwiftUI
import AppKit

struct CanvasCheckerboardView: View {
    let isDark: Bool

    private static var lightImage: NSImage?
    private static var darkImage: NSImage?

    var body: some View {
        Image(nsImage: checkerImage)
            .resizable(resizingMode: .tile)
    }

    private var checkerImage: NSImage {
        if isDark, let img = Self.darkImage { return img }
        if !isDark, let img = Self.lightImage { return img }
        let img = renderChecker(isDark: isDark)
        if isDark { Self.darkImage = img } else { Self.lightImage = img }
        return img
    }

    private func renderChecker(isDark: Bool) -> NSImage {
        let side: CGFloat = 18
        let size = NSSize(width: side * 2, height: side * 2)
        let img = NSImage(size: size)
        img.lockFocus()
        let light: NSColor = isDark ? .white.withAlphaComponent(0.18) : .white
        let dark: NSColor = isDark ? .white.withAlphaComponent(0.06) : .black.withAlphaComponent(0.045)
        let tiles: [(CGRect, NSColor)] = [
            (CGRect(x: 0, y: 0, width: side, height: side), light),
            (CGRect(x: side, y: 0, width: side, height: side), dark),
            (CGRect(x: 0, y: side, width: side, height: side), dark),
            (CGRect(x: side, y: side, width: side, height: side), light),
        ]
        for (rect, color) in tiles {
            color.setFill()
            NSBezierPath(rect: rect).fill()
        }
        img.unlockFocus()
        return img
    }
}
