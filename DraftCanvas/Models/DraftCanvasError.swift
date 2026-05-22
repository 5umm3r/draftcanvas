import Foundation

// MARK: - Errors

enum DraftCanvasError: LocalizedError {
    case invalidJSONLine(String)
    case invalidRequest(String)
    case processNotRunning
    case processExited
    case rpcError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case freePlanNotEntitled(message: String)
    case missingThreadID
    case missingGeneratedContent
    case unsupportedImageResult(String)
    case threadIDCollision(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSONLine(let line):
            return String(localized: "JSON行を解析できません: \(line)")
        case .invalidRequest(let message):
            return message
        case .processNotRunning:
            return String(localized: "codex app-server が起動していません。")
        case .processExited:
            return String(localized: "codex app-server が終了しました。")
        case .rpcError(let message):
            return message
        case .rateLimited:
            return String(localized: "レート制限に達しました。再試行中です。")
        case .timeout:
            return String(localized: "タイムアウトしました。")
        case .freePlanNotEntitled:
            return String(localized: "ChatGPT の有料プランが必要です。")
        case .missingThreadID:
            return String(localized: "thread/start のレスポンスから thread id を取得できませんでした。")
        case .missingGeneratedContent:
            return String(localized: "生成結果を取得できませんでした。ログを確認してください。")
        case .unsupportedImageResult(let value):
            return String(localized: "未対応の画像結果形式です: \(value.prefix(64))")
        case .threadIDCollision(let id):
            return String(localized: "内部エラー: thread ID が重複しました (\(id))。")
        }
    }
}

// MARK: - JSON helpers

extension JSONDecoder {
    static var projectDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var projectEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
