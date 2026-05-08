import Foundation

enum GenerationOutputMode: String, CaseIterable, Identifiable, Codable {
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
    var transparentBackground: Bool
    var outputMode: GenerationOutputMode
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
    var outputMode: GenerationOutputMode
    var originalPrompt: String
    var svgText: String?

    var isLocalImageInputSupported: Bool {
        outputMode == .raster
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

struct ProjectItem: Identifiable, Codable, Equatable {
    let id: UUID
    let projectID: UUID
    let prompt: String
    let revisedPrompt: String?
    let outputMode: GenerationOutputMode
    let aspectRatio: GenerationAspectRatio
    let transparentBackground: Bool
    let createdAt: Date
    let fileExtension: String
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        prompt: String,
        revisedPrompt: String? = nil,
        outputMode: GenerationOutputMode,
        aspectRatio: GenerationAspectRatio,
        transparentBackground: Bool,
        createdAt: Date = Date(),
        fileExtension: String,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.prompt = prompt
        self.revisedPrompt = revisedPrompt
        self.outputMode = outputMode
        self.aspectRatio = aspectRatio
        self.transparentBackground = transparentBackground
        self.createdAt = createdAt
        self.fileExtension = fileExtension
        self.errorMessage = errorMessage
    }

    func fileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).\(fileExtension)")
    }
}

// MARK: - ProjectStore

final class ProjectStore {
    struct Snapshot: Codable {
        var schemaVersion: Int = 2
        var projects: [Project] = []
        var items: [ProjectItem] = []
        var selectedProjectID: UUID? = nil
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
        return (try? JSONDecoder.projectDecoder.decode(Snapshot.self, from: data)) ?? Snapshot()
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
