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
    @Published var terminationRequested = false
    @Published var draftInputs: ProjectInputs = ProjectInputs()
    var lastRequestByProject: [UUID: GenerationRequest] = [:]
    var preparedRequestByRun: [UUID: GenerationRequest] = [:]
    var generationTasks: [UUID: [UUID: Task<Void, Never>]] = [:]
    var editSourceRefCounts: [UUID: Int] = [:]
    var attachmentRefCounts: [UUID: Int] = [:]

    // MARK: - 自動リトライ
    @AppStorage("autoRetryEnabled") var autoRetryEnabled: Bool = true
    var autoRetryCountByProject: [UUID: Int] = [:]    // run 単位のリトライ回数（上限3）
    var autoRetryTasks: [UUID: Task<Void, Never>] = [:]  // バックオフ中の予約タスク
    var autoRetryRequestByProject: [UUID: [UUID: GenerationRequest]] = [:]  // リトライ用リクエスト退避

    // MARK: - Global state
    @AppStorage("appAppearance") var appAppearanceRaw: String = "light"
    @AppStorage("completionSound") var completionSound: String = CompletionSoundOption.glass.rawValue
    @AppStorage("canvasSortOrder") var canvasSortOrderRaw: String = CanvasSortOrder.createdAtAscending.rawValue
    @AppStorage("placeholderAnimationStyle") var placeholderAnimationStyleRaw: String = PlaceholderAnimationStyle.aurora.rawValue
    var canvasSortOrder: CanvasSortOrder {
        get { CanvasSortOrder(rawValue: canvasSortOrderRaw) ?? .createdAtAscending }
        set {
            canvasSortOrderRaw = newValue.rawValue
            recomputeDisplayedItems()
        }
    }
    // canvasSortOrder と同じパターン: recomputeDisplayedItems() が @Published
    // displayedItemsSnapshot を更新するため、objectWillChange.send() は不要
    @AppStorage("canvasShowsBookmarkedOnly") var canvasShowsBookmarkedOnlyRaw: Bool = false
    var canvasShowsBookmarkedOnly: Bool {
        get { canvasShowsBookmarkedOnlyRaw }
        set {
            canvasShowsBookmarkedOnlyRaw = newValue
            recomputeDisplayedItems()
        }
    }
    @Published var projects: [Project] = []
    @Published var items: [ProjectItem] = [] {
        didSet {
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            if !isLoadingProjects {
                scheduleDerivedStateRecompute()
            }
        }
    }
    // items の全件 filter+sort+タグ再構築は要素1つの変更でも didSet ごとに走る。
    // 同一 runloop 内の連続変更（バッチ削除・複数追加等）を1回に束ねる。
    private var derivedStateRecomputeScheduled = false

    func scheduleDerivedStateRecompute() {
        guard !derivedStateRecomputeScheduled else { return }
        derivedStateRecomputeScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.derivedStateRecomputeScheduled = false
            self.recomputeDisplayedItems()
            self.rebuildAllTagsCache()
        }
    }
    private(set) var itemsByID: [UUID: ProjectItem] = [:]
    @Published private(set) var allTagsCache: [String] = []
    @Published var displayedItemsSnapshot: [ProjectItem] = []

    // MARK: - Search state
    @Published var sidebarSearchDraft: String = ""
    @Published private(set) var sidebarSearchCommitted: String = ""
    private var searchDebounceTask: Task<Void, Never>?
    private var preSearchSidebarSelection: SidebarSelection?

    var isSearchActive: Bool {
        if case .search = sidebarSelection { return true }
        return false
    }

    func onSearchDraftChanged(_ value: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.commitSearch() }
        }
    }

    func commitSearch() {
        let trimmed = sidebarSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            exitSearchMode(clearDraft: false)
            return
        }
        if preSearchSidebarSelection == nil {
            preSearchSidebarSelection = sidebarSelection
        }
        sidebarSearchCommitted = trimmed
        if !isSearchActive { sidebarSelection = .search }
        recomputeDisplayedItems()
    }

    func exitSearchMode(clearDraft: Bool) {
        searchDebounceTask?.cancel()
        sidebarSearchCommitted = ""
        if clearDraft { sidebarSearchDraft = "" }
        if let prev = preSearchSidebarSelection {
            sidebarSelection = prev
        } else if isSearchActive {
            sidebarSelection = .none
        }
        preSearchSidebarSelection = nil
        recomputeDisplayedItems()
    }
    @Published var activeEditProjectID: UUID?
    @Published var sidebarSelection: SidebarSelection = .none {
        didSet {
            guard sidebarSelection != oldValue, !isLoadingProjects else { return }
            activeEditProjectID = nil
            selectedJobID = nil
            selectedItemID = nil
            selectedItemIDs.removeAll()
            isSelectionMode = false
            recomputeDisplayedItems()
            saveState()
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
    var accountUsageStatusFetchedAt: Date?
    @Published var pendingRateLimitConfirmation: RateLimitConfirmation?
    @Published var pendingFreeAccountBlock = false
    @Published var isRefreshingAccountUsage = false
    var needsAccountUsageRefreshAfterGeneration = false
    @Published var preferredSaveFolder: URL?
    @Published var errorToast: String?
    @Published var accountUsagePrewarmFailed = false
    @Published var pendingLoginRequired = false
    @Published var codexVersion: String = "--"
    @Published var availableModels: [CodexModel] = []

    @Published var dismissedFailedJobIDs: Set<UUID> = []

    @Published var vectorizingItemIDs: Set<UUID> = []
    @Published var inpaintingTarget: ProjectItem? = nil
    @Published var sketchEditorTarget: SketchEditorTarget? = nil
    @Published var inpaintMode: InpaintMode = {
        let raw = UserDefaults.standard.string(forKey: "draftCanvas.inpaintMode") ?? "edit"
        return InpaintMode(rawValue: raw) ?? .edit
    }() {
        didSet { UserDefaults.standard.set(inpaintMode.rawValue, forKey: "draftCanvas.inpaintMode") }
    }
    @Published var exportRequest: ExportRequest? = nil
    @Published var exportingProjectID: UUID? = nil
    @Published var batchExportProgress: (done: Int, total: Int)? = nil
    @Published var filteringProjects: [FilteringProject] = [] {
        didSet { if !isLoadingProjects { scheduleDerivedStateRecompute() } }
    }
    var selectedFilteringProjectID: UUID? {
        get {
            if case .filtering(let id) = sidebarSelection { return id }
            return nil
        }
        set {
            if let id = newValue {
                sidebarSelection = .filtering(id)
            } else if case .filtering = sidebarSelection {
                sidebarSelection = .none
            }
        }
    }
    @Published var cropTarget: ProjectItem? = nil
    @Published var outpaintTarget: OutpaintTarget? = nil
    var outpaintInsetsCache: [UUID: OutpaintInsets] = [:]
    @Published var backgroundRemovalPreview: BackgroundRemovalPreview? = nil
    @Published var materialExtractionPreview: MaterialExtractionPreview? = nil
    @Published var extractingItemID: UUID? = nil
    @Published var upscalePreview: UpscalePreviewPayload? = nil
    @Published var upscaleRerunning: Bool = false
    @Published var importProgress: (done: Int, total: Int)? = nil
    @Published var importError: String? = nil
    @Published var focusPromptTrigger: UUID? = nil

    @Published var templates: [PromptTemplate] = []
    @Published var promptHistory: [PromptHistoryEntry] = []
    @Published var isTemplatePopoverPresented: Bool = false
    @Published var isHistoryPopoverPresented: Bool = false
    @Published var shouldFocusPromptAfterApply: Bool = false

    let client: CodexAppServerClient
    let accountClient: CodexAccountProviding
    let coordinator: GenerationCoordinator
    var projectStore: ProjectStore
    let preferredSaveFolderStore: PreferredSaveFolderStore
    var isLoadingProjects = false
    var vectorizationTasks: [UUID: Task<Void, Never>] = [:]
    var upscalingItemIDs: Set<UUID> = []
    var upscalingTasks: [UUID: Task<Void, Never>] = [:]
    var upscalingJobContexts: [UUID: (jobID: UUID, projectID: UUID)] = [:]
    // キャンセル後に同一アイテムへ再実行した際、旧タスクの遅延完了が
    // 新実行の状態を壊さないよう世代トークンで識別する
    var upscalingRunTokens: [UUID: UUID] = [:]
    var upscaleRerunTask: Task<Void, Never>?
    var backgroundRemovalTask: Task<Void, Never>?
    var backgroundRemovalJobContext: (jobID: UUID, projectID: UUID)?
    // 単一スロットのため、連続実行時に古いタスクの完了処理が
    // 新しい実行の状態を上書きしないよう世代トークンで識別する
    var backgroundRemovalRunToken: UUID?
    var materialExtractionTask: Task<Void, Never>?
    var materialExtractionJobContext: (jobID: UUID, projectID: UUID)?
    var materialExtractionRunToken: UUID?
    var accountUsageRefreshTask: Task<CodexAccountUsageStatus, Error>?
    var modelsRefreshTask: Task<Void, Never>?
    let activityTracker = ActivityTracker()
    var onAppendPromptText: ((String) -> Void)?
    var thumbnailStore: CanvasThumbnailStore
    let originalImageStore: CanvasOriginalImageStore
    var templateStore: PromptTemplateStore
    var historyStore: PromptHistoryStore
    @Published var syncMonitor: ICloudSyncMonitor?
    let imageLoader = ICloudImageLoader()
    let cacheEviction = ICloudCacheEviction()

    // 初期スナップショットのロード前に saveState が走ると空データで上書きするため、
    // ロード完了までは保存を禁止する
    private var hasLoadedInitialSnapshot = false

    // スナップショットは全プロジェクト・全アイテムを含むため、
    // 操作毎のメインスレッド同期保存はライブラリ規模に比例して UI をブロックする。
    // デバウンスで束ね、書き込みは直列シリアライザで順序保証する。
    private var pendingSaveTask: Task<Void, Never>?
    private var saveGeneration: UInt64 = 0
    private let saveSerializer = SnapshotSaveSerializer()

    init(
        projectStore: ProjectStore = ProjectStore(),
        preferredSaveFolderStore: PreferredSaveFolderStore = PreferredSaveFolderStore(),
        client: CodexAppServerClient = CodexAppServerClient(),
        accountClient: CodexAccountProviding? = nil,
        prewarmOnInit: Bool = true
    ) {
        DraftCanvasViewModel.migrateAppSupportDirectoryIfNeeded()
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"),
           let iCloudURL = ICloudSyncMonitor.iCloudContainerURL() {
            ProjectStore.migrateToICloudIfNeeded(iCloudRoot: iCloudURL)
        }
        self.client = client
        self.accountClient = accountClient ?? client
        self.coordinator = GenerationCoordinator(runner: CodexGenerationRunner(client: client))
        self.projectStore = projectStore
        self.preferredSaveFolderStore = preferredSaveFolderStore
        self.thumbnailStore = CanvasThumbnailStore(
            itemsDirectory: projectStore.itemsDirectory,
            useNoSync: projectStore.isInUbiquityContainer
        )
        self.originalImageStore = CanvasOriginalImageStore(loader: imageLoader, eviction: cacheEviction)
        self.templateStore = PromptTemplateStore(rootDirectory: projectStore.rootDirectory)
        self.historyStore = PromptHistoryStore(rootDirectory: projectStore.rootDirectory)
        saveSerializer.onWriteFailure = { [weak self] in
            Task { @MainActor [weak self] in
                self?.showError("プロジェクトの保存に失敗しました。ディスク容量と権限を確認してください")
            }
        }
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
        coordinator.onConcurrencyAdjusted = { [weak self] old, new in
            Task { @MainActor [weak self] in
                self?.logs.append("並列度を \(old) → \(new) に調整しました")
            }
        }
        // iCloud 配下では起動毎の一括削除は同期ノイズ（mtime 更新→再アップロード）を招くため行わない。
        // 起動パス上の同期 I/O を避けるためバックグラウンドで実行する。
        if !projectStore.isInUbiquityContainer {
            Task.detached(priority: .utility) { [store = projectStore] in
                store.cleanupAllAttachments()
            }
        }
        if projectStore.isInUbiquityContainer {
            let monitor = ICloudSyncMonitor()
            // start() 直後に gathering finish 通知が処理されるため、
            // ポリシーは start() 前に確定させる必要がある。
            // 順序が逆だと thumbsOnly ユーザーは初回集計だけ .eager 扱いになり、
            // 未 DL 原本が pending に混入して「同期中」表示が残留する。
            monitor.autoPullPolicy = ICloudAutoPullPolicy.load()
            self.syncMonitor = monitor
            monitor.start(containerURL: projectStore.rootDirectory)
            installForegroundRefreshObserver()
            enforceCacheLimitOnLaunchIfNeeded()
        }
        // iCloud 有効かつコンテナ未解決のままローカルをロードすると、
        // 差し替えまでの間の編集がローカル側に書かれて孤立する。
        // 解決完了（または解決不可の確定）までロードを遅延する。
        // 対象はデフォルトのローカルフォールバック時のみ（テスト等の注入ストアは除外）。
        if isAwaitingICloudResolution {
            isLoadingProjects = true
        } else {
            loadProjects()
            prefetchRecentProjectsIfNeeded()
            loadTemplates()
            loadHistory()
        }
        resolveICloudAsync()
        preferredSaveFolder = preferredSaveFolderStore.load()
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if prewarmOnInit {
            prewarmAndRefresh()
        }
    }

    func rebuildAllTagsCache() {
        allTagsCache = Array(Set(items.flatMap(\.tags))).sorted()
    }

    // url(forUbiquityContainerIdentifier:) はメインスレッドで nil を返す場合がある。
    // バックグラウンドで解決し、iCloud パスが得られたら stores を差し替えて再読み込みする。
    // iCloud 有効・コンテナ未解決・かつ現在のストアがデフォルトのローカル
    // フォールバックである場合のみ true。明示的に注入されたストア（テスト等）は
    // 非同期解決の対象にしない。
    private var isAwaitingICloudResolution: Bool {
        UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
            && !projectStore.isInUbiquityContainer
            && projectStore.rootDirectory.path == ProjectStore.localDefaultRootDirectory().path
    }

    private func resolveICloudAsync() {
        guard isAwaitingICloudResolution else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let url = ICloudSyncMonitor.iCloudContainerURL()
            await MainActor.run { [weak self] in
                guard let self, !self.projectStore.isInUbiquityContainer else { return }
                guard let url else {
                    // iCloud 解決不可（サインアウト等）→ ローカルストアで通常ロード
                    self.loadProjects()
                    self.loadTemplates()
                    self.loadHistory()
                    self.prefetchRecentProjectsIfNeeded()
                    return
                }
                ProjectStore.migrateToICloudIfNeeded(iCloudRoot: url)
                let newStore = ProjectStore(rootDirectory: url)
                self.projectStore = newStore
                self.thumbnailStore = CanvasThumbnailStore(
                    itemsDirectory: newStore.itemsDirectory,
                    useNoSync: true
                )
                self.templateStore = PromptTemplateStore(rootDirectory: url)
                self.historyStore = PromptHistoryStore(rootDirectory: url)
                let monitor = ICloudSyncMonitor()
                // start() 直後の gathering finish を正しいポリシーで処理するため、
                // autoPullPolicy は start() 前に設定する必要がある (順序逆転すると
                // thumbsOnly ユーザーの初回集計だけ .eager 扱いになり pending 残留)。
                monitor.autoPullPolicy = ICloudAutoPullPolicy.load()
                self.syncMonitor = monitor
                monitor.start(containerURL: url)
                self.installForegroundRefreshObserver()
                self.loadProjects()
                self.loadTemplates()
                self.loadHistory()
                self.enforceCacheLimitOnLaunchIfNeeded()
                self.prefetchRecentProjectsIfNeeded()
            }
        }
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

    func showError(_ message: String.LocalizationValue) {
        errorToast = String(localized: message)
    }

    // MARK: - Private

    private var foregroundRefreshObserver: NSObjectProtocol?

    private func installForegroundRefreshObserver() {
        // 複数回呼ばれても refresh が多重発火しないよう既存登録を解除する
        if let existing = foregroundRefreshObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        foregroundRefreshObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncMonitor?.refresh() }
        }
    }

    func loadProjects() {
        isLoadingProjects = true
        defer {
            isLoadingProjects = false
            hasLoadedInitialSnapshot = true
            recomputeDisplayedItems()
            rebuildAllTagsCache()
        }
        let snapshot = projectStore.load()
        if projectStore.lastLoadDataWasCorrupted {
            showError("プロジェクトデータが破損していたため読み込めませんでした。元ファイルは projects.json.corrupted- として保全されています")
            logs.append("projects.json のデコードに失敗。破損バックアップを作成して空の状態で起動します。")
        }
        projects = snapshot.projects
        items = snapshot.items
        filteringProjects = snapshot.filteringProjects
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
            filteringProjects: filteringProjects,
            sidebarSelection: sidebarSelection,
            expandedSections: expandedSections
        )
    }

    func saveState() {
        guard hasLoadedInitialSnapshot else { return }
        guard pendingSaveTask == nil else { return }
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.pendingSaveTask = nil
            self.saveGeneration += 1
            self.saveSerializer.writeAsync(
                self.makeSnapshot(),
                generation: self.saveGeneration,
                store: self.projectStore
            )
        }
    }

    func saveStateAsync() {
        saveState()
    }

    /// アプリ終了時など、デバウンスを待てない場面での即時同期保存
    func saveStateNow() {
        guard hasLoadedInitialSnapshot else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveGeneration += 1
        saveSerializer.writeSync(
            makeSnapshot(),
            generation: saveGeneration,
            store: projectStore
        )
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

    // MARK: - Relaunch support

    var hasProtectedInFlightWork: Bool {
        !generatingProjectIDs.isEmpty
            || exportingProjectID != nil
            || batchExportProgress != nil
    }

    func confirmTermination() {
        cancelInFlightWorkForRelaunch()
        terminationRequested = false
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    func cancelTermination() {
        terminationRequested = false
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
    }

    var hasInFlightWork: Bool {
        !generatingProjectIDs.isEmpty
            || !vectorizingItemIDs.isEmpty
            || !upscalingItemIDs.isEmpty
            || importProgress != nil
            || batchExportProgress != nil
            || exportingProjectID != nil
            || backgroundRemovalPreview != nil
            || materialExtractionPreview != nil
            || upscalePreview != nil
            || inpaintingTarget != nil
            || cropTarget != nil
            || outpaintTarget != nil
    }

    func cancelInFlightWorkForRelaunch() {
        activityTracker.endAll()
        for (_, runMap) in generationTasks { for (_, t) in runMap { t.cancel() } }
        generationTasks.removeAll()
        for (_, t) in vectorizationTasks { t.cancel() }
        vectorizationTasks.removeAll()
        for (_, t) in upscalingTasks { t.cancel() }
        upscalingTasks.removeAll()
        upscalingJobContexts.removeAll()
        upscaleRerunTask?.cancel()
        upscaleRerunTask = nil
        upscaleRerunning = false
        for (_, t) in autoRetryTasks { t.cancel() }
        autoRetryTasks.removeAll()
        autoRetryCountByProject.removeAll()
        autoRetryRequestByProject.removeAll()
        backgroundRemovalTask?.cancel()
        backgroundRemovalTask = nil
        backgroundRemovalJobContext = nil
        materialExtractionTask?.cancel()
        materialExtractionTask = nil
        materialExtractionJobContext = nil
        accountUsageRefreshTask?.cancel()
        accountUsageRefreshTask = nil
        isRefreshingAccountUsage = false

        generatingProjectIDs.removeAll()
        vectorizingItemIDs.removeAll()
        upscalingItemIDs.removeAll()
        importProgress = nil
        batchExportProgress = nil
        exportingProjectID = nil
        backgroundRemovalPreview = nil
        materialExtractionPreview = nil
        upscalePreview = nil
        inpaintingTarget = nil
        cropTarget = nil
        outpaintTarget = nil

        saveState()
    }

    func prepareForRelaunch() async {
        let tasksToAwait = generationTasks.values.flatMap { $0.values }
            + Array(vectorizationTasks.values)
            + Array(upscalingTasks.values)
            + Array(autoRetryTasks.values)
        cancelInFlightWorkForRelaunch()
        for task in tasksToAwait { await task.value }
    }
}

// MARK: - 起動時 LRU eviction

extension DraftCanvasViewModel {
    /// 起動直後に呼ぶ。原本のサイズと last access を集めて上限超過分を evict。
    /// 省容量モード OFF の場合は no-op (eager がローカルに pull し続けるため上限の意味が薄い)。
    func enforceCacheLimitOnLaunchIfNeeded() {
        guard syncMonitor != nil,
              ICloudAutoPullPolicy.load() == .thumbsOnly
        else { return }
        let eviction = self.cacheEviction
        let store = self.projectStore
        Task.detached(priority: .utility) {
            let entries = await collectEntries(rootDirectory: store.rootDirectory, eviction: eviction)
            let evictURLs = await eviction.enforceLimit(entries: entries)
            for url in evictURLs {
                ICloudCacheEviction.evict(url: url)
                await eviction.forgetAccess(url: url)
            }
        }
    }
}

// MARK: - 起動時プリフェッチ

extension DraftCanvasViewModel {
    /// 起動直後、updatedAt 降順で先頭 prefetchCount 件のプロジェクトに紐づく
    /// アイテム原本の DL を要求する。省容量モード (thumbsOnly) 時のみ実行。
    func prefetchRecentProjectsIfNeeded(prefetchCount: Int = 3, itemsPerProject: Int = 4) {
        guard let monitor = syncMonitor,
              ICloudAutoPullPolicy.load() == .thumbsOnly
        else { return }
        let recent = Array(projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(prefetchCount))
        let allItems = self.items
        let store = self.projectStore
        Task.detached(priority: .utility) {
            for project in recent {
                let head = Array(allItems.filter { $0.projectID == project.id }.prefix(itemsPerProject))
                for item in head {
                    let url = store.resolvedFileURL(for: item)
                    await MainActor.run { monitor.requestDownload(for: url) }
                }
            }
        }
    }
}

private func collectEntries(rootDirectory: URL, eviction: ICloudCacheEviction) async -> [ICloudCacheEntry] {
    let fm = FileManager.default
    let itemsDir = rootDirectory.appendingPathComponent("items")
    let keys: [URLResourceKey] = [.fileSizeKey, .ubiquitousItemDownloadingStatusKey]
    guard let enumerator = fm.enumerator(at: itemsDir, includingPropertiesForKeys: keys) else { return [] }
    // NSDirectoryEnumerator.makeIterator() は Swift 6 非同期コンテキストで使用不可。
    // URL と size を同期的に先に収集してから、actor 呼び出しを行う。
    var collected: [(url: URL, size: Int)] = []
    while let item = enumerator.nextObject() {
        guard let url = item as? URL else { continue }
        if url.lastPathComponent.hasPrefix(".thumbs") { continue }
        let vals = try? url.resourceValues(forKeys: Set(keys))
        guard let size = vals?.fileSize else { continue }
        // 未 DL のファイルはローカル副本を持たないが .fileSizeKey は論理サイズを返す。
        // これを容量に数えると、evict 済みのぶんまで超過扱いになって解放量 0 の
        // evict を繰り返し、実体のあるファイルまで際限なく削られる。
        if vals?.ubiquitousItemDownloadingStatus == .notDownloaded { continue }
        collected.append((url: url, size: size))
    }
    var entries: [ICloudCacheEntry] = []
    for item in collected {
        let last = (await eviction.lastAccess(url: item.url)) ?? .distantPast
        entries.append(.init(url: item.url, size: Int64(item.size), lastAccess: last))
    }
    return entries
}

/// スナップショット保存の直列化。
/// 並行する保存要求（デバウンス済み非同期保存と終了時の同期保存）が
/// 同一 projects.json へ順序不定に書き込むと古い内容が新しい内容を
/// 上書きするため、直列キュー + 世代番号で「新しい世代のみ書く」を保証する。
private final class SnapshotSaveSerializer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.draftcanvas.snapshot-save", qos: .utility)
    private var lastGeneration: UInt64 = 0
    // 書き込み失敗（ディスクフル・権限等）をユーザーに通知するためのフック
    var onWriteFailure: (@Sendable () -> Void)?

    func writeAsync(_ snapshot: ProjectStore.Snapshot, generation: UInt64, store: ProjectStore) {
        queue.async { self.write(snapshot, generation: generation, store: store) }
    }

    func writeSync(_ snapshot: ProjectStore.Snapshot, generation: UInt64, store: ProjectStore) {
        queue.sync { self.write(snapshot, generation: generation, store: store) }
    }

    private func write(_ snapshot: ProjectStore.Snapshot, generation: UInt64, store: ProjectStore) {
        guard generation > lastGeneration else { return }
        lastGeneration = generation
        if !store.save(snapshot) {
            onWriteFailure?()
        }
    }
}
