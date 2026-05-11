import Foundation
import SwiftUI

// MARK: - App Appearance

enum AppAppearance: String {
    case light, dark

    var next: AppAppearance {
        self == .light ? .dark : .light
    }

    var systemImage: String {
        self == .light ? "sun.max" : "moon"
    }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

// MARK: - Codex Model

struct CodexModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool
    let rating: ModelRating?
}

struct ModelRating: Equatable {
    let cost: String
    let smart: String
    let speed: String

    static let table: [String: ModelRating] = [
        "GPT-5.5":       .init(cost: "high", smart: "high", speed: "high"),
        "gpt-5.4":       .init(cost: "mid",  smart: "high", speed: "high"),
        "GPT-5.4-Mini":  .init(cost: "low",  smart: "mid",  speed: "high"),
        "gpt-5.3-codex": .init(cost: "low",  smart: "mid",  speed: "high"),
        "gpt-5.2":       .init(cost: "low",  smart: "low",  speed: "mid"),
    ]

    static func lookup(displayName: String) -> ModelRating? { table[displayName] }
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

    var widthOverHeight: CGFloat {
        switch self {
        case .square:    return 1.0
        case .portrait:  return 3.0 / 4.0
        case .story:     return 9.0 / 16.0
        case .landscape: return 4.0 / 3.0
        case .wide:      return 16.0 / 9.0
        }
    }
}

struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int
    var concurrency: Int
    var aspectRatio: GenerationAspectRatio = .square
    var editSource: GenerationEditSource? = nil
    var attachedImagePath: String? = nil
    var model: String = ""
    var reasoningEffort: String = "medium"

    var normalizedCount: Int {
        min(max(count, 1), 24)
    }

    var normalizedConcurrency: Int {
        min(max(concurrency, 1), normalizedCount)
    }
}

enum InpaintPurpose {
    case edit
    case remove
}

struct GenerationEditSource: Equatable {
    var projectItemID: UUID
    var filePath: String
    var originalPrompt: String
    var maskFilePath: String?
    var compositeFilePath: String?
    var inpaintPurpose: InpaintPurpose

    var isInpainting: Bool { maskFilePath != nil }

    init(
        projectItemID: UUID,
        filePath: String,
        originalPrompt: String,
        maskFilePath: String? = nil,
        compositeFilePath: String? = nil,
        inpaintPurpose: InpaintPurpose = .edit
    ) {
        self.projectItemID = projectItemID
        self.filePath = filePath
        self.originalPrompt = originalPrompt
        self.maskFilePath = maskFilePath
        self.compositeFilePath = compositeFilePath
        self.inpaintPurpose = inpaintPurpose
    }

    static func == (lhs: GenerationEditSource, rhs: GenerationEditSource) -> Bool {
        lhs.projectItemID == rhs.projectItemID &&
        lhs.filePath == rhs.filePath &&
        lhs.originalPrompt == rhs.originalPrompt &&
        lhs.maskFilePath == rhs.maskFilePath &&
        lhs.compositeFilePath == rhs.compositeFilePath
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
    var aspectRatio: GenerationAspectRatio
    var status: GenerationJobStatus
    var imageData: Data?
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        index: Int,
        prompt: String,
        aspectRatio: GenerationAspectRatio,
        status: GenerationJobStatus = .queued,
        imageData: Data? = nil,
        revisedPrompt: String? = nil,
        logs: [String] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.index = index
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.status = status
        self.imageData = imageData
        self.revisedPrompt = revisedPrompt
        self.logs = logs
        self.errorMessage = errorMessage
    }
}

// MARK: - AttachedImage

struct AttachedImage: Equatable {
    let id: UUID
    let filePath: String
    let originalFileName: String?

    init(id: UUID = UUID(), filePath: String, originalFileName: String? = nil) {
        self.id = id
        self.filePath = filePath
        self.originalFileName = originalFileName
    }
}

// MARK: - ProjectInputs

struct ProjectInputs: Equatable {
    var prompt: String = ""
    var count: Int = 1
    var concurrency: Int = 1
    var aspectRatio: GenerationAspectRatio = .square
    var editSource: GenerationEditSource? = nil
    var attachedImage: AttachedImage? = nil
    var model: String = ""
    var reasoningEffort: String = "medium"
}

// MARK: - CanvasSortOrder

enum CanvasSortOrder: String, CaseIterable, Identifiable {
    case createdAtAscending
    case createdAtDescending
    var id: String { rawValue }
    var label: String {
        switch self {
        case .createdAtAscending: return "作成日 古い順"
        case .createdAtDescending: return "作成日 新しい順"
        }
    }
    var systemImage: String {
        switch self {
        case .createdAtAscending: return "arrow.up"
        case .createdAtDescending: return "arrow.down"
        }
    }
}

// MARK: - Project

struct Project: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isAutoNamed: Bool
    let createdAt: Date
    var updatedAt: Date
    var model: String
    var reasoningEffort: String
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isAutoNamed: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        model: String = "",
        reasoningEffort: String = "medium",
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isAutoNamed = isAutoNamed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.isFavorite = isFavorite
    }
}

// MARK: - SmartProject

struct SmartProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tagConditions: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        tagConditions: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tagConditions = tagConditions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Project: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, isAutoNamed, createdAt, updatedAt, model, reasoningEffort, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isAutoNamed = try c.decode(Bool.self, forKey: .isAutoNamed)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? "medium"
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct ProjectItem: Identifiable, Equatable {
    let id: UUID
    var projectID: UUID
    let prompt: String
    let revisedPrompt: String?
    let aspectRatio: GenerationAspectRatio
    let createdAt: Date
    let errorMessage: String?
    var editedFromItemID: UUID?
    let hasSVG: Bool
    let isBackgroundRemoved: Bool
    let isImported: Bool
    var tags: [String]

    init(
        id: UUID = UUID(),
        projectID: UUID,
        prompt: String,
        revisedPrompt: String? = nil,
        aspectRatio: GenerationAspectRatio,
        createdAt: Date = Date(),
        errorMessage: String? = nil,
        editedFromItemID: UUID? = nil,
        hasSVG: Bool = false,
        isBackgroundRemoved: Bool = false,
        isImported: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.prompt = prompt
        self.revisedPrompt = revisedPrompt
        self.aspectRatio = aspectRatio
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.editedFromItemID = editedFromItemID
        self.hasSVG = hasSVG
        self.isBackgroundRemoved = isBackgroundRemoved
        self.isImported = isImported
        self.tags = tags
    }

    func fileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).png")
    }

    func svgFileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).svg")
    }
}

extension ProjectItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, projectID, prompt, revisedPrompt, aspectRatio, createdAt, errorMessage, editedFromItemID
        case hasSVG
        case isBackgroundRemoved
        case isImported
        case tags
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
        hasSVG = try c.decodeIfPresent(Bool.self, forKey: .hasSVG) ?? false
        isBackgroundRemoved = try c.decodeIfPresent(Bool.self, forKey: .isBackgroundRemoved) ?? false
        isImported = try c.decodeIfPresent(Bool.self, forKey: .isImported) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
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
        if hasSVG { try c.encode(hasSVG, forKey: .hasSVG) }
        if isBackgroundRemoved { try c.encode(isBackgroundRemoved, forKey: .isBackgroundRemoved) }
        if isImported { try c.encode(isImported, forKey: .isImported) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
    }
}

// MARK: - ProjectStore

final class ProjectStore: @unchecked Sendable {
    struct Snapshot: Codable {
        var projects: [Project] = []
        var items: [ProjectItem] = []
        var selectedProjectID: UUID? = nil
        var smartProjects: [SmartProject] = []
        var selectedSmartProjectID: UUID? = nil

        enum CodingKeys: String, CodingKey {
            case projects, items, selectedProjectID, smartProjects, selectedSmartProjectID
        }

        init(projects: [Project] = [], items: [ProjectItem] = [], selectedProjectID: UUID? = nil, smartProjects: [SmartProject] = [], selectedSmartProjectID: UUID? = nil) {
            self.projects = projects
            self.items = items
            self.selectedProjectID = selectedProjectID
            self.smartProjects = smartProjects
            self.selectedSmartProjectID = selectedSmartProjectID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
            items = try c.decodeIfPresent([ProjectItem].self, forKey: .items) ?? []
            selectedProjectID = try c.decodeIfPresent(UUID.self, forKey: .selectedProjectID)
            smartProjects = try c.decodeIfPresent([SmartProject].self, forKey: .smartProjects) ?? []
            selectedSmartProjectID = try c.decodeIfPresent(UUID.self, forKey: .selectedSmartProjectID)
        }
    }

    let rootDirectory: URL

    private var metadataURL: URL {
        rootDirectory.appendingPathComponent("projects.json")
    }

    var itemsDirectory: URL {
        rootDirectory.appendingPathComponent("items", isDirectory: true)
    }

    var masksDirectory: URL {
        rootDirectory.appendingPathComponent("masks", isDirectory: true)
    }

    var attachmentsDirectory: URL {
        rootDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    @discardableResult
    func writeAttachmentData(_ data: Data, id: UUID, fileExtension: String = "png") throws -> URL {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let url = attachmentsDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanupAttachment(id: UUID) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(id.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cleanupAllAttachments() {
        try? FileManager.default.removeItem(at: attachmentsDirectory)
    }

    @discardableResult
    func writeMaskData(_ data: Data, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_mask.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func writeCompositeData(_ data: Data, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_composite.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanupMaskFiles(id: UUID) {
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(id.uuidString)_mask.png"))
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(id.uuidString)_composite.png"))
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
        guard let snapshot = try? JSONDecoder.projectDecoder.decode(Snapshot.self, from: data) else {
            return Snapshot()
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

    @discardableResult
    func writeSVGData(_ data: Data, for item: ProjectItem) throws -> URL {
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let url = item.svgFileURL(in: rootDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteItemFile(_ item: ProjectItem) {
        try? FileManager.default.removeItem(at: item.fileURL(in: rootDirectory))
        if item.hasSVG {
            try? FileManager.default.removeItem(at: item.svgFileURL(in: rootDirectory))
        }
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Draft Canvas", isDirectory: true)
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

    var systemImageName: String {
        switch self {
        case .chatgpt:          return "person.crop.circle.fill"
        case .apiKey:           return "key.fill"
        case .amazonBedrock:    return "cloud.fill"
        case .unauthenticated:  return "person.crop.circle.badge.questionmark"
        case .unknown:          return "questionmark.circle"
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
    var primaryResetDate: Date?
    var secondaryResetDate: Date?

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
        secondaryResetText: nil,
        primaryResetDate: nil,
        secondaryResetDate: nil
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
            secondaryResetText: secondaryUsage.resetText,
            primaryResetDate: primaryUsage.resetDate,
            secondaryResetDate: secondaryUsage.resetDate
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
    ) -> (label: String, remainingFraction: Double?, resetText: String?, resetDate: Date?) {
        let resetDate = window.flatMap { parseResetDate(from: $0) }
        let resetText = resetDate.flatMap { formatRelativeReset(to: $0) }
        guard let usedPercent = numericValue(window?["usedPercent"]) else {
            return ("\(prefix) -", nil, resetText, resetDate)
        }
        let remainingPercent = min(100, max(0, 100 - usedPercent))
        return ("\(prefix) \(Int(remainingPercent.rounded()))%", remainingPercent / 100, resetText, resetDate)
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

enum DraftCanvasError: LocalizedError {
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

// MARK: - CompletionSoundOption

enum CompletionSoundOption: String, CaseIterable {
    case off = "off"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var displayName: String {
        switch self {
        case .off: return "オフ"
        default: return rawValue
        }
    }
}
