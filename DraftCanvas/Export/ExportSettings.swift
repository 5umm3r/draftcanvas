import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Codable {
    case png, jpeg, svg

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .svg: return "SVG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .svg: return "svg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .svg: return .svg
        }
    }
}

enum JPEGQualityPreset: Int, CaseIterable, Codable {
    case high98 = 98
    case mid80 = 80
    case low60 = 60

    var compressionFactor: CGFloat { CGFloat(rawValue) / 100.0 }

    var displayName: String {
        switch self {
        case .high98: return String(localized: "高 (98)")
        case .mid80: return String(localized: "中 (80)")
        case .low60: return String(localized: "低 (60)")
        }
    }
}

enum PNGOptimizationLevel: Int, CaseIterable, Codable {
    case fast = 0
    case max = 1

    var displayName: String {
        switch self {
        case .fast: return String(localized: "高速圧縮")
        case .max: return String(localized: "最大圧縮（ロッシー）")
        }
    }

    var isLossy: Bool { self == .max }
}

struct ExportSettings: Equatable {
    var format: ExportFormat
    var jpegQuality: JPEGQualityPreset
    var pngOptimize: Bool
    var pngLevel: PNGOptimizationLevel
    var resizeEnabled: Bool
    var resizeWidth: Int
    var resizeHeight: Int
}

enum ExportError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case resizeFailed

    var errorDescription: String? {
        switch self {
        case .encodeFailed: return String(localized: "エクスポートのエンコードに失敗しました。")
        case .decodeFailed: return String(localized: "画像のデコードに失敗しました。")
        case .resizeFailed: return String(localized: "リサイズに失敗しました。")
        }
    }
}

// MARK: - AppStorage キー
extension ExportSettings {
    enum StorageKey {
        static let format = "exportFormat"
        static let jpegQuality = "exportJPEGQuality"
        static let pngOptimize = "exportPNGOptimize"
        static let pngLevel = "exportPNGLevel"
        static let resizeEnabled = "exportResizeEnabled"
        static let resizeWidth = "exportResizeWidth"
        static let resizeHeight = "exportResizeHeight"
    }
}
