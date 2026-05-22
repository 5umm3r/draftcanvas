import CoreGraphics
import Foundation

struct CropParameters: Codable {
    var rect: CGRect
    var template: AspectTemplate
}

enum AspectTemplate: String, Codable, CaseIterable {
    case freeform
    case square
    case ratio4x3
    case ratio16x9
    case ratio9x16

    var ratio: CGFloat? {
        switch self {
        case .freeform: return nil
        case .square:   return 1.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio16x9: return 16.0 / 9.0
        case .ratio9x16: return 9.0 / 16.0
        }
    }

    var label: String {
        switch self {
        case .freeform:  return String(localized: "自由")
        case .square:    return String(localized: "1:1")
        case .ratio4x3:  return "4:3"
        case .ratio16x9: return "16:9"
        case .ratio9x16: return "9:16"
        }
    }
}
