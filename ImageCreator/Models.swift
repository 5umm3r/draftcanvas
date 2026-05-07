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
    var historyItemID: UUID
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

struct GenerationHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var prompt: String
    var outputMode: GenerationOutputMode
    var transparentBackground: Bool
    var aspectRatio: GenerationAspectRatio?
    var resultFilename: String
    var revisedPrompt: String?
    var errorMessage: String?

    var displayTitle: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題の生成物" : prompt
    }

    var fileExtension: String {
        switch outputMode {
        case .raster:
            return "png"
        case .svg:
            return "svg"
        }
    }

    func fileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent(resultFilename)
    }
}

struct GenerationHistoryStore {
    let rootDirectory: URL

    private var metadataURL: URL {
        rootDirectory.appendingPathComponent("history.json")
    }

    init(rootDirectory: URL = GenerationHistoryStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    func load() throws -> [GenerationHistoryItem] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return []
        }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder.historyDecoder.decode([GenerationHistoryItem].self, from: data)
    }

    @discardableResult
    func add(job: GenerationJob, request: GenerationRequest, createdAt: Date = Date()) throws -> GenerationHistoryItem {
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)

        let id = UUID()
        let filename = "\(id.uuidString).\(request.outputMode.historyFileExtension)"
        let item = GenerationHistoryItem(
            id: id,
            createdAt: createdAt,
            prompt: job.prompt,
            outputMode: request.outputMode,
            transparentBackground: request.transparentBackground,
            aspectRatio: request.aspectRatio,
            resultFilename: filename,
            revisedPrompt: job.revisedPrompt,
            errorMessage: job.errorMessage
        )

        try writeContent(for: job, outputMode: request.outputMode, to: item.fileURL(in: rootDirectory))

        var items = try load()
        items.insert(item, at: 0)
        try save(items)
        return item
    }

    func save(_ items: [GenerationHistoryItem]) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.historyEncoder.encode(items)
        try data.write(to: metadataURL, options: .atomic)
    }

    private var itemsDirectory: URL {
        rootDirectory.appendingPathComponent("items", isDirectory: true)
    }

    private func writeContent(for job: GenerationJob, outputMode: GenerationOutputMode, to url: URL) throws {
        switch outputMode {
        case .raster:
            guard let imageData = job.imageData else {
                throw ImageCreatorError.missingGeneratedContent
            }
            try imageData.write(to: url, options: .atomic)
        case .svg:
            guard let svgText = job.svgText, let data = svgText.data(using: .utf8) else {
                throw ImageCreatorError.svgExtractionFailed
            }
            try data.write(to: url, options: .atomic)
        }
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Image Creator", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }
}

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

private extension GenerationOutputMode {
    var historyFileExtension: String {
        switch self {
        case .raster:
            return "png"
        case .svg:
            return "svg"
        }
    }
}

private extension JSONDecoder {
    static var historyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var historyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
