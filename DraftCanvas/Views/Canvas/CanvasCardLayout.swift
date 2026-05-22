import SwiftUI

enum CanvasCardLayout {
    static let baseSquareSide: CGFloat = 220
    static let baseSpacing: CGFloat = 20
    static let minSpacing: CGFloat = 8

    static func size(for ratio: CGFloat, zoom: CGFloat) -> CGSize {
        let r = max(ratio, 0.01)
        let longSide = baseSquareSide * zoom
        if r >= 1 {
            return CGSize(width: longSide, height: longSide / r)
        } else {
            return CGSize(width: longSide * r, height: longSide)
        }
    }

    static func spacing(zoom: CGFloat) -> CGFloat {
        max(minSpacing, baseSpacing * zoom)
    }
}
