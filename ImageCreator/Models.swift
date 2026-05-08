import Foundation

enum GenerationAspectRatio: String, CaseIterable, Identifiable, Codable {
    case square
    case portrait
    case story
    case landscape
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square:
            return "正方形"
        case .portrait:
            return "ポートレート"
        case .story:
            return "ストーリー"
        case .landscape:
            return "横長"
        case .wide:
            return "ワイドスクリーン"
        }
    }

    var value: String {
        switch self {
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

    var promptDescription: String {
        "\(value) \(rawValue)"
    }
}

struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int
    var concurrency: Int
    var aspectRatio: GenerationAspectRatio = .square
    var editSource: GenerationEditSource? = nil

    var normalizedCount: Int {
        min(max(count, 1), 24)
    }

    var normalizedConcurrency: Int {
        min(max(concurrency, 1), normalizedCount)
    }
}

struct GenerationEditSource: Equatable {
    var projectItemID: UUID
    var filePath: String
    var originalPrompt: String
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
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        index: Int,
        prompt: String,
        status: GenerationJobStatus = .queued,
        imageData: Data? = nil,
        revisedPrompt: String? = nil,
        logs: [String] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.index = index
        self.prompt = prompt
        self.status = status
        self.imageData = imageData
        self.revisedPrompt = revisedPrompt
        self.logs = logs
        self.errorMessage = errorMessage
    }
}

// MARK: - ProjectInputs

struct ProjectInputs: Equatable {
    var prompt: String = ""
    var count: Int = 1
    var concurrency: Int = 1
    var aspectRatio: GenerationAspectRatio = .square
    var editSource: GenerationEditSource? = nil
}

// MARK: - Project

struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isAutoNamed: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isAutoNamed: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isAutoNamed = isAutoNamed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectItem: Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let prompt: String
    let revisedPrompt: String?
    let aspectRatio: GenerationAspectRatio
    let createdAt: Date
    let errorMessage: String?
    let editedFromItemID: UUID?

    fileprivate let legacyOutputModeWasSVG: Bool

    init(
        id: UUID = UUID(),
        projectID: UUID,
        prompt: String,
        revisedPrompt: String? = nil,
        aspectRatio: GenerationAspectRatio,
        createdAt: Date = Date(),
        errorMessage: String? = nil,
        editedFromItemID: UUID? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.prompt = prompt
        self.revisedPrompt = revisedPrompt
        self.aspectRatio = aspectRatio
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.editedFromItemID = editedFromItemID
        self.legacyOutputModeWasSVG = false
    }

    func fileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).png")
    }
}

extension ProjectItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, projectID, prompt, revisedPrompt, aspectRatio, createdAt, errorMessage, editedFromItemID
        case outputMode, transparentBackground, fileExtension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        prompt = try c.decode(String.self, forKey: .prompt)
        revisedPrompt = try c.decodeIfPresent(String.self, forKey: .revisedPrompt)
        aspectRatio = try c.decodeIfPresent(GenerationAspectRatio.self, forKey: .aspectRatio) ?? .square
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        editedFromItemID = try c.decodeIfPresent(UUID.self, forKey: .editedFromItemID)
        let legacyMode = try c.decodeIfPresent(String.self, forKey: .outputMode)
        legacyOutputModeWasSVG = (legacyMode == "svg")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(prompt, forKey: .prompt)
        try c.encodeIfPresent(revisedPrompt, forKey: .revisedPrompt)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(editedFromItemID, forKey: .editedFromItemID)
    }
}

// MARK: - ProjectStore

final class ProjectStore: @unchecked Sendable {
    struct Snapshot: Codable {
        var schemaVersion: Int = 3
        var projects: [Project] = []
        var items: [ProjectItem] = []
        var selectedProjectID: UUID? = nil
        var droppedSVGCount: Int = 0
    }

    let rootDirectory: URL

    private var metadataURL: URL {
        rootDirectory.appendingPathComponent("projects.json")
    }

    var itemsDirectory: URL {
        rootDirectory.appendingPathComponent("items", isDirectory: true)
    }

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    func load() -> Snapshot {
        guard
            FileManager.default.fileExists(atPath: metadataURL.path),
            let data = try? Data(contentsOf: metadataURL)
        else {
            return Snapshot()
        }
        guard var snapshot = try? JSONDecoder.projectDecoder.decode(Snapshot.self, from: data) else {
            return Snapshot()
        }

        if snapshot.schemaVersion < 3 {
            let dropped = snapshot.items.filter { $0.legacyOutputModeWasSVG }
            for item in dropped {
                let svgURL = rootDirectory.appendingPathComponent("items")
                    .appendingPathComponent("\(item.id.uuidString).svg")
                try? FileManager.default.removeItem(at: svgURL)
            }
            snapshot.droppedSVGCount = dropped.count
            snapshot.items.removeAll(where: { $0.legacyOutputModeWasSVG })
            snapshot.schemaVersion = 3
            save(snapshot)
        }

        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.projectEncoder.encode(snapshot) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    @discardableResult
    func writeItemData(_ data: Data, for item: ProjectItem) throws -> URL {
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let url = item.fileURL(in: rootDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteItemFile(_ item: ProjectItem) {
        try? FileManager.default.removeItem(at: item.fileURL(in: rootDirectory))
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Image Creator", isDirectory: true)
    }
}

// MARK: - ProjectNaming

enum ProjectNaming {
    static let maxCharacters = 20

    static func summarize(_ prompt: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !normalized.isEmpty else { return defaultName() }
        if normalized.count <= maxCharacters { return normalized }
        return String(normalized.prefix(maxCharacters)) + "…"
    }

    static func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "新規プロジェクト " + f.string(from: Date())
    }
}

// MARK: - Persistence helpers

struct PreferredSaveFolderStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "preferredSaveFolderBookmark") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> URL? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale {
            return url
        }

        guard let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func save(_ directory: URL) throws {
        do {
            let data = try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            userDefaults.set(data, forKey: key)
        } catch {
            userDefaults.set(Data(directory.path.utf8), forKey: key)
        }
    }
}

// MARK: - Codex types

struct CodexImageResult: Equatable {
    let imageID: String
    let data: Data
    let revisedPrompt: String?
}

struct CodexTurnResult: Equatable {
    var imageResult: CodexImageResult?
    var assistantText: String
    var logs: [String]
}

enum AccountKind: Equatable {
    case chatgpt, apiKey, amazonBedrock, unauthenticated, unknown

    var japaneseLabel: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .apiKey: return "APIキー"
        case .amazonBedrock: return "Amazon Bedrock"
        case .unauthenticated: return "未ログイン"
        case .unknown: return "不明"
        }
    }
}

struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsageLabel: String
    var secondaryUsageLabel: String
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?
    var accountEmail: String?
    var accountKind: AccountKind
    var primaryResetText: String?
    var secondaryResetText: String?

    static let unavailable = CodexAccountUsageStatus(
        accountLabel: "アカウント未取得",
        planLabel: "-",
        primaryUsageLabel: "5h -",
        secondaryUsageLabel: "weekly -",
        primaryUsageRemainingFraction: nil,
        secondaryUsageRemainingFraction: nil,
        accountEmail: nil,
        accountKind: .unauthenticated,
        primaryResetText: nil,
        secondaryResetText: nil
    )

    static func parse(accountResponse: [String: Any], rateLimitsResponse: [String: Any]) -> CodexAccountUsageStatus {
        let account = accountResponse["account"] as? [String: Any]
        let accountType = account?["type"] as? String
        let planLabel = (account?["planType"] as? String)
            ?? planType(from: rateLimitsResponse)
            ?? "-"

        let accountKind: AccountKind
        let accountEmail: String?
        let accountLabel: String
        switch accountType {
        case "chatgpt":
            accountKind = .chatgpt
            accountEmail = account?["email"] as? String
            accountLabel = accountEmail ?? "ChatGPT"
        case "apiKey":
            accountKind = .apiKey
            accountEmail = nil
            accountLabel = "API Key"
        case "amazonBedrock":
            accountKind = .amazonBedrock
            accountEmail = nil
            accountLabel = "Amazon Bedrock"
        case .some(let value):
            accountKind = .unknown
            accountEmail = nil
            accountLabel = value
        case .none:
            accountKind = .unauthenticated
            accountEmail = nil
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
            secondaryUsageRemainingFraction: secondaryUsage.remainingFraction,
            accountEmail: accountEmail,
            accountKind: accountKind,
            primaryResetText: primaryUsage.resetText,
            secondaryResetText: secondaryUsage.resetText
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

    private static func usageStatus(
        prefix: String,
        window: [String: Any]?
    ) -> (label: String, remainingFraction: Double?, resetText: String?) {
        let resetText = window.flatMap { parseResetDate(from: $0) }.flatMap { formatRelativeReset(to: $0) }
        guard let usedPercent = numericValue(window?["usedPercent"]) else {
            return ("\(prefix) -", nil, resetText)
        }
        let remainingPercent = min(100, max(0, 100 - usedPercent))
        return ("\(prefix) \(Int(remainingPercent.rounded()))%", remainingPercent / 100, resetText)
    }

    private static func parseResetDate(from window: [String: Any]) -> Date? {
        let keys = ["resetsAt", "resetAt", "nextResetAt", "resetsAtUTC", "resetTime"]
        for key in keys {
            guard let value = window[key] else { continue }
            if let str = value as? String {
                for options: ISO8601DateFormatter.Options in [
                    [.withInternetDateTime, .withFractionalSeconds],
                    [.withInternetDateTime]
                ] {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = options
                    if let date = f.date(from: str) { return date }
                }
            }
            if let num = numericValue(value) {
                // > 1e12 ならミリ秒判定、それ以外はUNIX秒
                let ts = num > 1e12 ? num / 1000 : num
                return Date(timeIntervalSince1970: ts)
            }
        }
        return nil
    }

    private static func formatRelativeReset(to target: Date) -> String? {
        // UTC差分秒で計算。タイムゾーン変換不要
        let diff = target.timeIntervalSince(Date())
        if diff <= 60 { return "もうすぐ" }
        let totalMin = Int(diff / 60)
        let hours = totalMin / 60
        let mins = totalMin % 60
        if hours < 1 { return "あと \(totalMin)m" }
        if hours < 24 { return mins > 0 ? "あと \(hours)h\(mins)m" : "あと \(hours)h" }
        let days = hours / 24
        let hrs = hours % 24
        return hrs > 0 ? "あと \(days)d \(hrs)h" : "あと \(days)d"
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

// MARK: - Errors

enum ImageCreatorError: LocalizedError {
    case invalidJSONLine(String)
    case invalidRequest(String)
    case processNotRunning
    case processExited
    case rpcError(String)
    case missingThreadID
    case missingGeneratedContent
    case unsupportedImageResult(String)

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
        }
    }
}

// MARK: - JSON helpers

private extension JSONDecoder {
    static var projectDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var projectEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
