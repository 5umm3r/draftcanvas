import SwiftUI
import AppKit

@MainActor
enum EditorCheckerboard {
    private static var patternColor: NSColor?

    static func fill(_ rect: CGRect, in ctx: CGContext) {
        let color = patternColor ?? makePatternColor()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        color.setFill()
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func makePatternColor() -> NSColor {
        let side: CGFloat = 12
        let size = NSSize(width: side * 2, height: side * 2)
        let img = NSImage(size: size)
        img.lockFocus()
        let light = NSColor(white: 0.82, alpha: 1)
        let dark = NSColor(white: 0.65, alpha: 1)
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
        let c = NSColor(patternImage: img)
        patternColor = c
        return c
    }
}

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
