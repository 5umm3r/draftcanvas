import Foundation

enum MaterialExtractionError: Error, LocalizedError {
    case imageDecodeFailed
    case noInstancesFound
    case maskGenerationFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:    return String(localized: "画像ファイルを読み込めませんでした")
        case .noInstancesFound:     return String(localized: "素材を検出できませんでした")
        case .maskGenerationFailed: return String(localized: "マスクの生成に失敗しました")
        case .encodeFailed:         return String(localized: "結果画像の保存に失敗しました")
        }
    }
}
