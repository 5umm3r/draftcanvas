import Foundation

enum GenerationOutputMode: String, CaseIterable, Identifiable {
    case raster
    case svg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raster:
            return "Image"
        case .svg:
            return "SVG"
        }
    }
}

struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int
    var concurrency: Int
    var transparentBackground: Bool
    var outputMode: GenerationOutputMode

    var normalizedCount: Int {
        min(max(count, 1), 24)
    }

    var normalizedConcurrency: Int {
        min(max(concurrency, 1), normalizedCount)
    }
}

enum GenerationJobStatus: String {
    case queued
    case running
    case succeeded
    case failed

    var title: String {
        switch self {
        case .queued:
            return "待機中"
        case .running:
            return "生成中"
        case .succeeded:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}

struct GenerationJob: Identifiable, Equatable {
    let id: UUID
    let index: Int
    var prompt: String
    var status: GenerationJobStatus
    var imageData: Data?
    var svgText: String?
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        index: Int,
        prompt: String,
        status: GenerationJobStatus = .queued,
        imageData: Data? = nil,
        svgText: String? = nil,
        revisedPrompt: String? = nil,
        logs: [String] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.index = index
        self.prompt = prompt
        self.status = status
        self.imageData = imageData
        self.svgText = svgText
        self.revisedPrompt = revisedPrompt
        self.logs = logs
        self.errorMessage = errorMessage
    }
}

struct CodexImageResult: Equatable {
    let imageID: String
    let data: Data
    let revisedPrompt: String?
}

struct CodexTurnResult: Equatable {
    var imageResult: CodexImageResult?
    var svgText: String?
    var assistantText: String
    var logs: [String]
}

struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsageLabel: String
    var secondaryUsageLabel: String
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?

    static let unavailable = CodexAccountUsageStatus(
        accountLabel: "アカウント未取得",
        planLabel: "-",
        primaryUsageLabel: "5h -",
        secondaryUsageLabel: "weekly -",
        primaryUsageRemainingFraction: nil,
        secondaryUsageRemainingFraction: nil
    )

    static func parse(accountResponse: [String: Any], rateLimitsResponse: [String: Any]) -> CodexAccountUsageStatus {
        let account = accountResponse["account"] as? [String: Any]
        let accountType = account?["type"] as? String
        let planLabel = (account?["planType"] as? String)
            ?? planType(from: rateLimitsResponse)
            ?? "-"

        let accountLabel: String
        switch accountType {
        case "chatgpt":
            accountLabel = account?["email"] as? String ?? "ChatGPT"
        case "apiKey":
            accountLabel = "API Key"
        case "amazonBedrock":
            accountLabel = "Amazon Bedrock"
        case .some(let value):
            accountLabel = value
        case .none:
            accountLabel = "未ログイン"
        }

        let rateLimits = preferredRateLimits(from: rateLimitsResponse)
        let primaryUsage = usageStatus(prefix: "5h", window: rateLimits?["primary"] as? [String: Any])
        let secondaryUsage = usageStatus(prefix: "weekly", window: rateLimits?["secondary"] as? [String: Any])
        return CodexAccountUsageStatus(
            accountLabel: accountLabel,
            planLabel: planLabel,
            primaryUsageLabel: primaryUsage.label,
            secondaryUsageLabel: secondaryUsage.label,
            primaryUsageRemainingFraction: primaryUsage.remainingFraction,
            secondaryUsageRemainingFraction: secondaryUsage.remainingFraction
        )
    }

    private static func preferredRateLimits(from response: [String: Any]) -> [String: Any]? {
        if
            let byID = response["rateLimitsByLimitId"] as? [String: Any],
            let codex = byID["codex"] as? [String: Any]
        {
            return codex
        }
        return response["rateLimits"] as? [String: Any]
    }

    private static func planType(from response: [String: Any]) -> String? {
        preferredRateLimits(from: response)?["planType"] as? String
    }

    private static func usageStatus(prefix: String, window: [String: Any]?) -> (label: String, remainingFraction: Double?) {
        guard let usedPercent = numericValue(window?["usedPercent"]) else {
            return ("\(prefix) -", nil)
        }
        let remainingPercent = min(100, max(0, 100 - usedPercent))
        return ("\(prefix) \(Int(remainingPercent.rounded()))%", remainingPercent / 100)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}

enum ImageCreatorError: LocalizedError {
    case invalidJSONLine(String)
    case invalidRequest(String)
    case processNotRunning
    case processExited
    case rpcError(String)
    case missingThreadID
    case missingGeneratedContent
    case unsupportedImageResult(String)
    case svgExtractionFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSONLine(let line):
            return "JSON行を解析できません: \(line)"
        case .invalidRequest(let message):
            return message
        case .processNotRunning:
            return "codex app-server が起動していません。"
        case .processExited:
            return "codex app-server が終了しました。"
        case .rpcError(let message):
            return message
        case .missingThreadID:
            return "thread/start のレスポンスから thread id を取得できませんでした。"
        case .missingGeneratedContent:
            return "生成結果を取得できませんでした。ログを確認してください。"
        case .unsupportedImageResult(let value):
            return "未対応の画像結果形式です: \(value.prefix(64))"
        case .svgExtractionFailed:
            return "Codexの返答からSVGを抽出できませんでした。"
        }
    }
}
