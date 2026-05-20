import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Codable {
    case png, jpeg, svg, tiff, pdf

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .svg: return "SVG"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .svg: return "svg"
        case .tiff: return "tiff"
        case .pdf: return "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .svg: return .svg
        case .tiff: return .tiff
        case .pdf: return .pdf
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
    var dpi: ExportDPI
    var tiffCompression: TIFFCompression
    var pdfCompression: PDFImageCompression
}

enum ExportDPI: Int, CaseIterable, Codable {
    case dpi72 = 72
    case dpi150 = 150
    case dpi300 = 300
    case dpi600 = 600

    var displayName: String {
        switch self {
        case .dpi72:  return String(localized: "72 dpi（画面）")
        case .dpi150: return String(localized: "150 dpi（簡易印刷）")
        case .dpi300: return String(localized: "300 dpi（高品質印刷）")
        case .dpi600: return String(localized: "600 dpi（商業印刷）")
        }
    }
}


enum TIFFCompression: String, CaseIterable, Codable {
    case lzw

    var displayName: String {
        switch self {
        case .lzw: return String(localized: "LZW（推奨）")
        }
    }
}

enum PDFImageCompression: String, CaseIterable, Codable {
    case lossless
    case jpegHigh
    case jpegMedium

    var displayName: String {
        switch self {
        case .lossless:    return String(localized: "可逆（Flate）")
        case .jpegHigh:    return String(localized: "JPEG 高品質")
        case .jpegMedium:  return String(localized: "JPEG 中品質")
        }
    }
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
        static let dpi = "exportDPI"
        static let tiffCompression = "exportTIFFCompression"
        static let pdfCompression = "exportPDFCompression"
    }
}
