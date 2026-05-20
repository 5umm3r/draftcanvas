import Foundation
import CoreGraphics

// MARK: - CodableColor

struct CodableColor: Equatable, Codable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    var cgColor: CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    static let black   = CodableColor(r: 0,        g: 0,        b: 0,        a: 1)
    static let red     = CodableColor(r: 0.898,    g: 0.224,    b: 0.208,    a: 1)
    static let blue    = CodableColor(r: 0.118,    g: 0.533,    b: 0.898,    a: 1)
    static let green   = CodableColor(r: 0.263,    g: 0.627,    b: 0.278,    a: 1)
    static let purple  = CodableColor(r: 0.557,    g: 0.141,    b: 0.667,    a: 1)

    static let presets: [CodableColor] = [black, red, blue, green, purple]
}

// MARK: - SketchStroke

struct SketchStroke: Equatable, Codable {
    let points: [CGPoint]
    let radius: CGFloat
    let color: CodableColor
    let isEraser: Bool
}

// MARK: - AttachmentKind

enum AttachmentKind: String, Codable, Equatable {
    case regular
    case sketch
}
