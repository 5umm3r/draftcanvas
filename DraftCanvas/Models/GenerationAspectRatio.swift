import Foundation
import CoreGraphics

enum GenerationAspectRatio: String, CaseIterable, Identifiable, Codable {
    case auto
    case square
    case portrait
    case story
    case landscape
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return String(localized: "自動")
        case .square:
            return String(localized: "正方形")
        case .portrait:
            return String(localized: "ポートレート")
        case .story:
            return String(localized: "ストーリー")
        case .landscape:
            return String(localized: "横長")
        case .wide:
            return String(localized: "ワイドスクリーン")
        }
    }

    var value: String {
        switch self {
        case .auto:
            return "auto"
        case .square:
            return "1:1"
        case .portrait:
            return "3:4"
        case .story:
            return "9:16"
        case .landscape:
            return "4:3"
        case .wide:
            return "16:9"
        }
    }

    var displayLabel: String {
        self == .auto ? String(localized: "自動") : value
    }

    var promptDescription: String {
        // 「1:1 square」のような ratio 表記は image gen モデルが size フィールドとして
        // ツール引数に付与しがち (Codex CLI が deny_unknown_fields で拒否) →
        // 自然言語のみで指示することで size 誤送信を抑止
        switch self {
        case .auto:      return "any composition that best fits the content"
        case .square:    return "a square shape"
        case .portrait:  return "a portrait (taller than wide) shape"
        case .story:     return "a tall vertical story shape"
        case .landscape: return "a horizontal landscape shape"
        case .wide:      return "a wide cinematic horizontal shape"
        }
    }

    var widthOverHeight: CGFloat {
        switch self {
        case .auto:      return 1.0
        case .square:    return 1.0
        case .portrait:  return 3.0 / 4.0
        case .story:     return 9.0 / 16.0
        case .landscape: return 4.0 / 3.0
        case .wide:      return 16.0 / 9.0
        }
    }
}
