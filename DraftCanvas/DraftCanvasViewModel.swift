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
        set { canvasSortOrderRaw = newValue.rawValue }
    }
    @Published var projects: [Project] = []
    @Published var items: [ProjectItem] = []
    @Published var selectedProjectID: UUID? {
        didSet {
            guard selectedProjectID != oldValue, !isLoadingProjects else { return }
            selectedJobID = nil
            selectedItemID = nil
            selectedItemIDs.removeAll()
            isSelectionMode = false
            let snapshot = makeSnapshot()
            Task.detached(priority: .background) { [store = projectStore] in
                store.save(snapshot)
            }
        }
    }
    @Published var selectedJobID: UUID?
    @Published var selectedItemID: UUID?
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var isSelectionMode: Bool = false
    @Published var logs: [String] = []
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

    let client: CodexAppServerClient
    let coordinator: GenerationCoordinator
    let projectStore: ProjectStore
    let preferredSaveFolderStore: PreferredSaveFolderStore
    var isLoadingProjects = false
    var vectorizationTasks: [UUID: Task<Void, Never>] = [:]
    var enhanceTask: Task<Void, Never>?
    var onReplacePromptText: ((String) -> Void)?
    let imageCache = NSCache<NSURL, NSImage>()

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
        client.onLog = { [weak self] message in
            Task { @MainActor in
                self?.logs.append(message)
            }
        }
        projectStore.cleanupAllAttachments()
        loadProjects()
        preferredSaveFolder = preferredSaveFolderStore.load()
        prewarmAndRefresh()
    }

    // MARK: - Private

    func loadProjects() {
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        let snapshot = projectStore.load()
        projects = snapshot.projects
        items = snapshot.items
        selectedProjectID = snapshot.selectedProjectID
        for project in projects {
            var inputs = ProjectInputs()
            inputs.model = project.model
            inputs.reasoningEffort = project.reasoningEffort
            inputsByProject[project.id] = inputs
        }
    }

    func makeSnapshot() -> ProjectStore.Snapshot {
        var snapshot = ProjectStore.Snapshot()
        snapshot.projects = projects
        snapshot.items = items
        snapshot.selectedProjectID = selectedProjectID
        return snapshot
    }

    func saveState() {
        projectStore.save(makeSnapshot())
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

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
