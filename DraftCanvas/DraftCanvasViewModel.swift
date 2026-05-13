import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class DraftCanvasViewModel: ObservableObject {
    // MARK: - Per-project state
    @Published var inputsByProject: [UUID: ProjectInputs] = [:]
    @Published var jobsByProject: [UUID: [GenerationJob]] = [:]
    @Published var generatingProjectIDs: Set<UUID> = []
    @Published var draftInputs: ProjectInputs = ProjectInputs()

    // MARK: - Global state
    @AppStorage("appAppearance") var appAppearanceRaw: String = "light"
    @AppStorage("totalGeneratedImages") var totalGeneratedImages: Int = 0
    @AppStorage("session5hCount") var session5hCount: Int = 0
    @AppStorage("sessionWeeklyCount") var sessionWeeklyCount: Int = 0
    @AppStorage("session5hResetEpoch") var session5hResetEpoch: Double = 0
    @AppStorage("sessionWeeklyResetEpoch") var sessionWeeklyResetEpoch: Double = 0
    // syncSessionWindows のリセット時に直近生成分を保持するためのカウンタ（永続化不要）
    var pendingFiveHDelta = 0
    var pendingWeeklyDelta = 0
    @AppStorage("completionSound") var completionSound: String = CompletionSoundOption.glass.rawValue
    @AppStorage("canvasSortOrder") var canvasSortOrderRaw: String = CanvasSortOrder.createdAtAscending.rawValue
    var canvasSortOrder: CanvasSortOrder {
        get { CanvasSortOrder(rawValue: canvasSortOrderRaw) ?? .createdAtAscending }
        set {
            canvasSortOrderRaw = newValue.rawValue
            recomputeDisplayedItems()
        }
    }
    @Published var projects: [Project] = []
    @Published var items: [ProjectItem] = [] {
        didSet {
            if !isLoadingProjects {
                recomputeDisplayedItems()
                rebuildAllTagsCache()
            }
        }
    }
    @Published private(set) var allTagsCache: [String] = []
    @Published var displayedItemsSnapshot: [ProjectItem] = []
    @Published var sidebarSelection: SidebarSelection = .none {
        didSet {
            guard sidebarSelection != oldValue, !isLoadingProjects else { return }
            selectedJobID = nil
            selectedItemID = nil
            selectedItemIDs.removeAll()
            isSelectionMode = false
            recomputeDisplayedItems()
            let snapshot = makeSnapshot()
            Task.detached(priority: .background) { [store = projectStore] in
                store.save(snapshot)
            }
        }
    }
    @Published var expandedSections: [String: Bool] = [:]

    var selectedProjectID: UUID? {
        get {
            if case .project(let id) = sidebarSelection { return id }
            return nil
        }
        set {
            if let id = newValue {
                sidebarSelection = .project(id)
            } else if case .project = sidebarSelection {
                sidebarSelection = .none
            }
        }
    }

    var isAllImagesSelected: Bool {
        if case .allImages = sidebarSelection { return true }
        return false
    }
    @Published var selectedJobID: UUID?
    @Published var selectedItemID: UUID?
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var isSelectionMode: Bool = false
    @Published var logs: [String] = []
    private var logBuffer: [String] = []
    private var logFlushTask: Task<Void, Never>?
    @Published var accountUsageStatus = CodexAccountUsageStatus.unavailable
    @Published var isRefreshingAccountUsage = false
    @Published var preferredSaveFolder: URL?
    @Published var errorToast: String?
    @Published var accountUsagePrewarmFailed = false
    @Published var isLoggingOut = false
    @Published var codexVersion: String = "--"
    @Published var availableModels: [CodexModel] = []

    @Published var vectorizingItemIDs: Set<UUID> = []
    @Published var inpaintingTarget: ProjectItem? = nil
    @Published var inpaintMode: InpaintMode = .edit
    @Published var isEnhancingPrompt = false
    @Published var exportRequest: ExportRequest? = nil
    @Published var exportingProjectID: UUID? = nil
    @Published var batchExportProgress: (done: Int, total: Int)? = nil
    @Published var smartProjects: [SmartProject] = [] {
        didSet { if !isLoadingProjects { recomputeDisplayedItems() } }
    }
    var selectedSmartProjectID: UUID? {
        get {
            if case .smart(let id) = sidebarSelection { return id }
            return nil
        }
        set {
            if let id = newValue {
                sidebarSelection = .smart(id)
            } else if case .smart = sidebarSelection {
                sidebarSelection = .none
            }
        }
    }
    @Published var backgroundRemovalPreview: BackgroundRemovalPreview? = nil
    @Published var importProgress: (done: Int, total: Int)? = nil
    @Published var importError: String? = nil

    let client: CodexAppServerClient
    let coordinator: GenerationCoordinator
    let projectStore: ProjectStore
    let preferredSaveFolderStore: PreferredSaveFolderStore
    var isLoadingProjects = false
    var vectorizationTasks: [UUID: Task<Void, Never>] = [:]
    var enhanceTask: Task<Void, Never>?
    var onReplacePromptText: ((String) -> Void)?
    let thumbnailStore: CanvasThumbnailStore

    init(
        projectStore: ProjectStore = ProjectStore(),
        preferredSaveFolderStore: PreferredSaveFolderStore = PreferredSaveFolderStore()
    ) {
        DraftCanvasViewModel.migrateAppSupportDirectoryIfNeeded()
        let client = CodexAppServerClient()
        self.client = client
        self.coordinator = GenerationCoordinator(runner: CodexGenerationRunner(client: client))
        self.projectStore = projectStore
        self.preferredSaveFolderStore = preferredSaveFolderStore
        self.thumbnailStore = CanvasThumbnailStore(itemsDirectory: projectStore.itemsDirectory)
        client.onLog = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logBuffer.append(message)
                if self.logFlushTask == nil {
                    self.logFlushTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        if self.logs.count + self.logBuffer.count > 1000 {
                            self.logs = Array(self.logs.suffix(900))
                        }
                        self.logs.append(contentsOf: self.logBuffer)
                        self.logBuffer.removeAll()
                        self.logFlushTask = nil
                    }
                }
            }
        }
        projectStore.cleanupAllAttachments()
        loadProjects()
        preferredSaveFolder = preferredSaveFolderStore.load()
        prewarmAndRefresh()
    }

    func rebuildAllTagsCache() {
        allTagsCache = Array(Set(items.flatMap(\.tags))).sorted()
    }

    func appendLog(_ message: String) {
        if logs.count >= 1000 {
            logs.removeFirst(logs.count - 900)
        }
        logs.append(message)
        #if DEBUG
        let msg = message
        Task.detached(priority: .utility) {
            Self.appendToLogFile(msg)
        }
        #endif
    }

    // MARK: - Private

    func loadProjects() {
        isLoadingProjects = true
        defer {
            isLoadingProjects = false
            recomputeDisplayedItems()
            rebuildAllTagsCache()
        }
        let snapshot = projectStore.load()
        projects = snapshot.projects
        items = snapshot.items
        smartProjects = snapshot.smartProjects
        sidebarSelection = snapshot.sidebarSelection
        expandedSections = snapshot.expandedSections
        for project in projects {
            var inputs = ProjectInputs()
            inputs.model = project.model
            inputs.reasoningEffort = project.reasoningEffort
            inputsByProject[project.id] = inputs
        }
        thumbnailStore.backfillMissing(items: items) { [store = projectStore] item in
            store.resolvedFileURL(for: item)
        }
    }

    func makeSnapshot() -> ProjectStore.Snapshot {
        ProjectStore.Snapshot(
            projects: projects,
            items: items,
            smartProjects: smartProjects,
            sidebarSelection: sidebarSelection,
            expandedSections: expandedSections
        )
    }

    func saveState() {
        projectStore.save(makeSnapshot())
    }

    func saveStateAsync() {
        let snapshot = makeSnapshot()
        Task.detached(priority: .background) { [store = projectStore] in
            store.save(snapshot)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    #if DEBUG
    nonisolated private static let logFile: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DraftCanvas")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("canvas.log")
    }()

    nonisolated private static func appendToLogFile(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile.path),
           let fh = try? FileHandle(forWritingTo: logFile) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: logFile)
        }
    }
    #endif

    private static func migrateAppSupportDirectoryIfNeeded() {
        let migrationKey = "draftcanvas.migration.appSupportDirRenamed.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let oldURL = base.appendingPathComponent("Image Creator", isDirectory: true)
        let newURL = base.appendingPathComponent("Draft Canvas", isDirectory: true)

        guard fm.fileExists(atPath: oldURL.path), !fm.fileExists(atPath: newURL.path) else { return }
        try? fm.moveItem(at: oldURL, to: newURL)
    }
}
