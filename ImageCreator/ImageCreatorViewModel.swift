import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class ImageCreatorViewModel: ObservableObject {
    // MARK: - Per-project state
    @Published var inputsByProject: [UUID: ProjectInputs] = [:]
    @Published var jobsByProject: [UUID: [GenerationJob]] = [:]
    @Published var generatingProjectIDs: Set<UUID> = []
    @Published var draftInputs: ProjectInputs = ProjectInputs()

    // MARK: - Global state
    @AppStorage("appAppearance") var appAppearanceRaw: String = "light"
    @AppStorage("totalGeneratedImages") var totalGeneratedImages: Int = 0
    @AppStorage("completionSound") var completionSound: String = CompletionSoundOption.glass.rawValue
    @Published var projects: [Project] = []
    @Published var items: [ProjectItem] = []
    @Published var selectedProjectID: UUID? {
        didSet {
            guard selectedProjectID != oldValue, !isLoadingProjects else { return }
            selectedJobID = nil
            selectedItemID = nil
            let snapshot = makeSnapshot()
            Task.detached(priority: .background) { [store = projectStore] in
                store.save(snapshot)
            }
        }
    }
    @Published var selectedJobID: UUID?
    @Published var selectedItemID: UUID?
    @Published var logs: [String] = []
    @Published var accountUsageStatus = CodexAccountUsageStatus.unavailable
    @Published var isRefreshingAccountUsage = false
    @Published var preferredSaveFolder: URL?
    @Published var errorToast: String?
    @Published var accountUsagePrewarmFailed = false
    @Published var isLoggingOut = false
    @Published private(set) var availableModels: [CodexModel] = []

    @Published var vectorizingItemIDs: Set<UUID> = []
    @Published var inpaintingTarget: ProjectItem? = nil

    private let client: CodexAppServerClient
    private let coordinator: GenerationCoordinator
    private let projectStore: ProjectStore
    private let preferredSaveFolderStore: PreferredSaveFolderStore
    private var isLoadingProjects = false
    private var vectorizationTasks: [UUID: Task<Void, Never>] = [:]
    let imageCache = NSCache<NSURL, NSImage>()

    init(
        projectStore: ProjectStore = ProjectStore(),
        preferredSaveFolderStore: PreferredSaveFolderStore = PreferredSaveFolderStore()
    ) {
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
        loadProjects()
        preferredSaveFolder = preferredSaveFolderStore.load()
        prewarmAndRefresh()
    }

    // MARK: - Computed (current project)

    var currentInputs: ProjectInputs {
        if let id = selectedProjectID, let inputs = inputsByProject[id] {
            return inputs
        }
        return draftInputs
    }

    var currentJobs: [GenerationJob] {
        selectedProjectID.flatMap { jobsByProject[$0] } ?? []
    }

    var isGeneratingForSelected: Bool {
        selectedProjectID.map { generatingProjectIDs.contains($0) } ?? false
    }

    func binding<T>(for keyPath: WritableKeyPath<ProjectInputs, T>) -> Binding<T> {
        Binding(
            get: { self.currentInputs[keyPath: keyPath] },
            set: { newValue in
                if let id = self.selectedProjectID {
                    var inputs = self.inputsByProject[id] ?? ProjectInputs()
                    inputs[keyPath: keyPath] = newValue
                    self.inputsByProject[id] = inputs
                    self.syncProjectModelEffort(for: id, inputs: inputs)
                } else {
                    self.draftInputs[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func syncProjectModelEffort(for projectID: UUID, inputs: ProjectInputs) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard projects[idx].model != inputs.model || projects[idx].reasoningEffort != inputs.reasoningEffort else { return }
        projects[idx].model = inputs.model
        projects[idx].reasoningEffort = inputs.reasoningEffort
        saveState()
    }

    var selectedJob: GenerationJob? {
        guard let selectedJobID else { return currentJobs.first }
        return currentJobs.first { $0.id == selectedJobID }
    }

    var itemsForSelectedProject: [ProjectItem] {
        guard let selectedProjectID else { return [] }
        return items
            .filter { $0.projectID == selectedProjectID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var preferredSaveFolderLabel: String {
        preferredSaveFolder?.lastPathComponent ?? "未選択"
    }

    var isEditingHistoryItem: Bool {
        currentInputs.editSource != nil
    }

    var canGenerate: Bool {
        !currentInputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGeneratingForSelected
    }

    var preferredColorScheme: ColorScheme {
        (AppAppearance(rawValue: appAppearanceRaw) ?? .light).colorScheme
    }

    func cycleAppearance() {
        let current = AppAppearance(rawValue: appAppearanceRaw) ?? .light
        appAppearanceRaw = current.next.rawValue
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(initialName: String? = nil, resetInputs: Bool = true) -> Project {
        let name = initialName ?? ProjectNaming.defaultName()
        let project = Project(name: name, isAutoNamed: true)
        projects.append(project)
        if resetInputs {
            inputsByProject[project.id] = ProjectInputs()
        } else {
            inputsByProject[project.id] = draftInputs
            draftInputs = ProjectInputs()
        }
        selectedProjectID = project.id  // didSet → saveState
        return project
    }

    func renameProject(id: UUID, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].name = trimmed.isEmpty ? ProjectNaming.defaultName() : trimmed
        projects[index].isAutoNamed = false
        projects[index].updatedAt = Date()
        saveState()
    }

    func deleteProject(id: UUID) {
        for item in items where item.projectID == id {
            projectStore.deleteItemFile(item)
        }
        items.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        inputsByProject.removeValue(forKey: id)
        jobsByProject.removeValue(forKey: id)
        generatingProjectIDs.remove(id)
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id  // didSet → saveState
        } else {
            saveState()
        }
    }

    var sortedProjects: [Project] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func moveProject(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveState()
    }

    // MARK: - Generation

    func generate() {
        guard canGenerate else { return }
        // availableModels 未取得または model 未設定なら isDefault モデルで埋める
        if currentInputs.model.isEmpty, let fallback = availableModels.first(where: \.isDefault)?.id ?? availableModels.first?.id {
            if let id = selectedProjectID {
                inputsByProject[id]?.model = fallback
            } else {
                draftInputs.model = fallback
            }
        }

        let inputs = currentInputs
        let promptText = inputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let targetProjectID: UUID
        if let existing = selectedProjectID, projects.contains(where: { $0.id == existing }) {
            targetProjectID = existing
            // Auto-rename if still auto-named and no items yet
            if let idx = projects.firstIndex(where: { $0.id == existing }),
               projects[idx].isAutoNamed,
               items.filter({ $0.projectID == existing }).isEmpty {
                projects[idx].name = ProjectNaming.summarize(promptText)
                projects[idx].updatedAt = Date()
                saveState()
            }
        } else {
            let newProject = createProject(initialName: ProjectNaming.summarize(promptText), resetInputs: false)
            targetProjectID = newProject.id
        }

        let request = GenerationRequest(
            prompt: promptText,
            count: inputs.count,
            concurrency: inputs.concurrency,
            aspectRatio: inputs.aspectRatio,
            editSource: inputs.editSource,
            model: inputs.model,
            reasoningEffort: inputs.reasoningEffort
        )

        jobsByProject[targetProjectID] = []
        generatingProjectIDs.insert(targetProjectID)
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")
        if let editSource = inputs.editSource {
            logs.append("アイテムを再編集します: \(editSource.filePath)")
        }

        Task {
            let results = await coordinator.run(request: request) { [weak self] job in
                await MainActor.run {
                    guard let self else { return }
                    self.upsert(job, into: targetProjectID)
                }
            }

            await MainActor.run {
                self.jobsByProject[targetProjectID] = results
                if self.selectedProjectID == targetProjectID {
                    let firstSucceeded = results.first(where: { $0.status == .succeeded })?.id ?? results.first?.id
                    self.selectedJobID = firstSucceeded
                }
                self.persistSucceededJobs(results, request: request, projectID: targetProjectID)
                self.generatingProjectIDs.remove(targetProjectID)
                if self.generatingProjectIDs.isEmpty {
                    self.onAllJobsCompleted(results: results)
                }
                if var inputs = self.inputsByProject[targetProjectID] {
                    if let editSource = inputs.editSource, editSource.isInpainting {
                        self.projectStore.cleanupMaskFiles(id: editSource.projectItemID)
                    }
                    inputs.editSource = nil
                    self.inputsByProject[targetProjectID] = inputs
                }
                self.logs.append("全ジョブが終了しました。")
                self.refreshAccountUsage()
            }
        }
    }

    func refreshAccountUsage() {
        guard !isRefreshingAccountUsage else { return }

        isRefreshingAccountUsage = true
        accountUsagePrewarmFailed = false
        logs.append("Codexアカウントと使用量を取得します。")

        Task {
            do {
                let status = try await self.client.readAccountUsageStatus()
                await MainActor.run {
                    self.accountUsageStatus = status
                    self.isRefreshingAccountUsage = false
                    self.logs.append("Codexアカウントと使用量を更新しました。")
                }
            } catch {
                await MainActor.run {
                    self.accountUsageStatus = .unavailable
                    self.isRefreshingAccountUsage = false
                    self.accountUsagePrewarmFailed = true
                    self.logs.append("Codexアカウントと使用量の取得に失敗しました: \(error.localizedDescription)")
                }
            }
        }
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        Task {
            do {
                _ = try await client.sendRequest(method: "account/logout")
                await MainActor.run {
                    self.accountUsageStatus = .unavailable
                    self.isLoggingOut = false
                    self.logs.append("ログアウトしました。")
                }
                refreshAccountUsage()
            } catch {
                await MainActor.run {
                    self.isLoggingOut = false
                    self.errorToast = "ログアウトに失敗しました"
                    self.logs.append("ログアウト失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    private func prewarmAndRefresh() {
        accountUsagePrewarmFailed = false
        Task {
            await refreshAvailableModels()
        }
        refreshAccountUsage()
    }

    func refreshAvailableModels() async {
        do {
            let models = try await client.listModels(includeHidden: false)
            self.availableModels = models
            normalizeProjectModelSelection()
        } catch {
            logs.append("モデル一覧取得失敗: \(error.localizedDescription)")
        }
    }

    private func normalizeProjectModelSelection() {
        let validIDs = Set(availableModels.map(\.id))
        guard let fallbackID = availableModels.first(where: \.isDefault)?.id
                ?? availableModels.first?.id else { return }

        for index in projects.indices {
            if projects[index].model.isEmpty || !validIDs.contains(projects[index].model) {
                projects[index].model = fallbackID
            }
            if let model = availableModels.first(where: { $0.id == projects[index].model }),
               !model.supportedReasoningEfforts.contains(projects[index].reasoningEffort) {
                projects[index].reasoningEffort = model.defaultReasoningEffort
            }
        }
        // draftInputs も同期
        if draftInputs.model.isEmpty || !validIDs.contains(draftInputs.model) {
            draftInputs.model = fallbackID
        }
        // inputsByProject も同期
        for (key, var inputs) in inputsByProject {
            if inputs.model.isEmpty || !validIDs.contains(inputs.model) {
                inputs.model = fallbackID
                inputsByProject[key] = inputs
            }
        }
        saveState()
    }

    func stopServer() {
        client.stop()
        logs.append("codex app-server を停止しました。")
    }

    func cancelEditingHistoryItem() {
        guard let id = selectedProjectID else { return }
        var inputs = inputsByProject[id] ?? ProjectInputs()
        if let editSource = inputs.editSource, editSource.isInpainting {
            projectStore.cleanupMaskFiles(id: editSource.projectItemID)
        }
        inputs.editSource = nil
        inputsByProject[id] = inputs
    }

    // MARK: - Item actions

    func edit(item: ProjectItem) {
        guard let id = selectedProjectID else { return }
        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        var inputs = inputsByProject[id] ?? ProjectInputs()
        inputs.prompt = item.prompt
        inputs.aspectRatio = item.aspectRatio
        inputs.editSource = GenerationEditSource(
            projectItemID: item.id,
            filePath: fileURL.path,
            originalPrompt: item.prompt
        )
        inputsByProject[id] = inputs
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].updatedAt = Date()
        }
        logs.append("アイテムを再編集対象にしました: \(fileURL.path)")
    }

    func inpaint(item: ProjectItem) {
        inpaintingTarget = item
    }

    func applyInpaintingMask(item: ProjectItem, strokes: [MaskStroke]) {
        guard let id = selectedProjectID else { return }

        let fileURL = item.fileURL(in: projectStore.rootDirectory)

        Task.detached(priority: .userInitiated) {
            do {
                let originalData = try Data(contentsOf: fileURL)
                let imgSource = CGImageSourceCreateWithData(originalData as CFData, nil)
                let imgProps = imgSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                let pw = imgProps?[kCGImagePropertyPixelWidth] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init)
                    ?? 1024
                let ph = imgProps?[kCGImagePropertyPixelHeight] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init)
                    ?? 1024
                let canvasSize = CGSize(width: pw, height: ph)

                guard let maskData = InpaintingMaskCompositor.renderMask(from: strokes, canvasSize: canvasSize) else {
                    await MainActor.run { self.errorToast = "マスク画像の生成に失敗しました。" }
                    return
                }

                let compositeData = try InpaintingMaskCompositor.composite(
                    originalImageData: originalData,
                    maskData: maskData
                )

                let store = await MainActor.run { self.projectStore }
                let maskURL = try store.writeMaskData(maskData, id: item.id)
                let compositeURL = try store.writeCompositeData(compositeData, id: item.id)

                await MainActor.run {
                    var inputs = self.inputsByProject[id] ?? ProjectInputs()
                    inputs.prompt = item.prompt
                    inputs.aspectRatio = item.aspectRatio
                    inputs.editSource = GenerationEditSource(
                        projectItemID: item.id,
                        filePath: fileURL.path,
                        originalPrompt: item.prompt,
                        maskFilePath: maskURL.path,
                        compositeFilePath: compositeURL.path
                    )
                    self.inputsByProject[id] = inputs
                    self.inpaintingTarget = nil
                    self.logs.append("マスク編集を設定しました: \(item.id)")
                }
            } catch {
                await MainActor.run {
                    self.errorToast = "マスクの処理に失敗しました: \(error.localizedDescription)"
                    self.logs.append("マスク編集処理エラー: \(error.localizedDescription)")
                }
            }
        }
    }

    func removeBackground(item: ProjectItem) {
        guard let projectID = selectedProjectID else { return }

        let job = GenerationJob(
            index: jobsByProject[projectID]?.count ?? 0,
            prompt: "背景除去: \(item.prompt.prefix(30))",
            aspectRatio: item.aspectRatio
        )
        upsert(job, into: projectID)

        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        let itemAspectRatio = item.aspectRatio
        let itemPrompt = item.prompt

        Task {
            var running = job
            running.status = .running
            await MainActor.run { [weak self] in self?.upsert(running, into: projectID) }

            do {
                let inputData = try Data(contentsOf: fileURL)
                let outputData = try await BackgroundRemover.process(data: inputData)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var completed = running
                    completed.status = .succeeded
                    completed.imageData = outputData
                    self.upsert(completed, into: projectID)

                    let newItem = ProjectItem(projectID: projectID, prompt: itemPrompt, aspectRatio: itemAspectRatio, isBackgroundRemoved: true)
                    do {
                        try self.projectStore.writeItemData(outputData, for: newItem)
                        self.items.append(newItem)
                        if let img = NSImage(data: outputData) {
                            self.imageCache.setObject(img, forKey: self.fileURL(for: newItem) as NSURL)
                        }
                        if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                            self.projects[idx].updatedAt = Date()
                        }
                        self.saveState()
                        self.logs.append("背景除去完了: \(newItem.id)")
                    } catch {
                        self.errorToast = "背景除去結果の保存に失敗しました"
                        self.logs.append("背景除去結果の保存に失敗: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var failed = running
                    failed.status = .failed
                    failed.errorMessage = error.localizedDescription
                    self.upsert(failed, into: projectID)
                    let message = (error as? BackgroundRemovalError)?.localizedDescription
                        ?? "背景除去に失敗しました"
                    self.errorToast = message
                    self.logs.append("背景除去失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    func deleteItem(_ item: ProjectItem) {
        projectStore.deleteItemFile(item)
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id { selectedItemID = nil }
        if let idx = projects.firstIndex(where: { $0.id == item.projectID }) {
            projects[idx].updatedAt = Date()
        }
        saveState()
    }

    func reveal(item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL(in: projectStore.rootDirectory)])
    }

    func fileURL(for item: ProjectItem) -> URL {
        item.fileURL(in: projectStore.rootDirectory)
    }

    func cachedImage(for item: ProjectItem) -> NSImage? {
        let url = fileURL(for: item) as NSURL
        if let cached = imageCache.object(forKey: url) { return cached }
        guard let img = NSImage(contentsOf: url as URL) else { return nil }
        imageCache.setObject(img, forKey: url)
        return img
    }

    func exportItem(_ item: ProjectItem) {
        guard let project = projects.first(where: { $0.id == item.projectID }) else { return }
        let ordinal = ordinalForItem(item, in: item.projectID)
        let base = ExportNaming.baseFilename(forProjectName: project.name, ordinal: ordinal)
        runExportPanel(baseFilename: base) { [weak self] dest, format in
            guard let self else { return }
            let pngData = try Data(contentsOf: item.fileURL(in: self.projectStore.rootDirectory))
            try self.writeExport(pngData: pngData, to: dest, format: format, item: item)
        }
    }

    func vectorize(item: ProjectItem) {
        guard let projectID = selectedProjectID else { return }

        vectorizingItemIDs.insert(item.id)

        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        let itemAspectRatio = item.aspectRatio
        let itemPrompt = item.prompt
        let itemID = item.id

        let task = Task {
            do {
                let inputData = try Data(contentsOf: fileURL)
                let result = try await ImageVectorizer.process(data: inputData)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.vectorizingItemIDs.remove(itemID)
                    self.vectorizationTasks.removeValue(forKey: itemID)

                    let newItem = ProjectItem(
                        projectID: projectID,
                        prompt: itemPrompt,
                        aspectRatio: itemAspectRatio,
                        hasSVG: true
                    )
                    do {
                        try self.projectStore.writeItemData(result.previewPNGData, for: newItem)
                        try self.projectStore.writeSVGData(result.svgData, for: newItem)
                        self.items.append(newItem)
                        if let img = NSImage(data: result.previewPNGData) {
                            self.imageCache.setObject(img, forKey: self.fileURL(for: newItem) as NSURL)
                        }
                        if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                            self.projects[idx].updatedAt = Date()
                        }
                        self.saveState()
                        self.logs.append("ベクター化完了: \(newItem.id)")
                    } catch {
                        self.errorToast = "ベクター化結果の保存に失敗しました"
                        self.logs.append("ベクター化結果の保存に失敗: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.vectorizingItemIDs.remove(itemID)
                    self.vectorizationTasks.removeValue(forKey: itemID)
                    guard !(error is CancellationError) else { return }
                    let message = (error as? ImageVectorizationError)?.localizedDescription
                        ?? "ベクター化に失敗しました"
                    self.errorToast = message
                    self.logs.append("ベクター化失敗: \(error.localizedDescription)")
                }
            }
        }
        vectorizationTasks[item.id] = task
    }

    func cancelVectorization(for item: ProjectItem) {
        vectorizationTasks[item.id]?.cancel()
        vectorizationTasks.removeValue(forKey: item.id)
        vectorizingItemIDs.remove(item.id)
    }

    func exportSelected() {
        guard let job = selectedJob, let pngData = job.imageData else { return }
        let projectName = projects.first(where: { $0.id == selectedProjectID })?.name ?? "Untitled"
        let base = ExportNaming.baseFilename(forProjectName: projectName, ordinal: job.index + 1)
        runExportPanel(baseFilename: base) { [weak self] dest, format in
            try self?.writeExport(pngData: pngData, to: dest, format: format)
        }
    }

    func ordinalForItem(_ item: ProjectItem, in projectID: UUID) -> Int {
        let sorted = items
            .filter { $0.projectID == projectID }
            .sorted { $0.createdAt < $1.createdAt }
        return (sorted.firstIndex(of: item) ?? 0) + 1
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "生成物を保存するときの既定フォルダを選択してください。"
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            try preferredSaveFolderStore.save(directory)
            preferredSaveFolder = directory
            logs.append("保存先フォルダを設定しました: \(directory.path)")
        } catch {
            logs.append("保存先フォルダの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func upsert(_ job: GenerationJob, into projectID: UUID) {
        var jobs = jobsByProject[projectID] ?? []
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        jobsByProject[projectID] = jobs
    }

    private func runExportPanel(
        baseFilename: String,
        handler: @escaping (URL, ExportFormat) throws -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = preferredSaveFolder
        let controller = ExportPanelController(panel: panel, baseFilename: baseFilename)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let resolved = ensureUniqueURL(url)
            try handler(resolved, controller.selectedFormat)
            logs.append("エクスポートしました: \(resolved.path)")
        } catch {
            logs.append("エクスポートに失敗しました: \(error.localizedDescription)")
        }
        _ = controller
    }

    private func writeExport(pngData: Data, to url: URL, format: ExportFormat, item: ProjectItem? = nil) throws {
        let data: Data
        switch format {
        case .png:
            data = pngData
        case .jpeg:
            data = try ImageEncoder.jpegData(fromPNG: pngData)
        case .svg:
            if let item, item.hasSVG,
               let svgData = try? Data(contentsOf: item.svgFileURL(in: projectStore.rootDirectory)) {
                data = svgData
            } else {
                data = try ImageEncoder.svgWrapping(pngData: pngData)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private func ensureUniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for n in 1...999 {
            let candidate = dir.appendingPathComponent(String(format: "%@-%d.%@", stem, n, ext))
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private func loadProjects() {
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
        if snapshot.droppedSVGCount > 0 {
            logs.append("既存SVGアイテム \(snapshot.droppedSVGCount)件を削除しました（SVG生成は廃止されました）")
        }
    }

    private func makeSnapshot() -> ProjectStore.Snapshot {
        var snapshot = ProjectStore.Snapshot()
        snapshot.projects = projects
        snapshot.items = items
        snapshot.selectedProjectID = selectedProjectID
        return snapshot
    }

    private func saveState() {
        projectStore.save(makeSnapshot())
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func onAllJobsCompleted(results: [GenerationJob]) {
        if completionSound != CompletionSoundOption.off.rawValue {
            NSSound(named: NSSound.Name(completionSound))?.play()
        }
        let succeeded = results.filter { $0.status == .succeeded }.count
        let failed = results.filter { $0.status == .failed }.count
        sendCompletionNotification(succeeded: succeeded, failed: failed)
    }

    private func sendCompletionNotification(succeeded: Int, failed: Int) {
        let content = UNMutableNotificationContent()
        content.title = "画像生成完了"
        content.body = failed > 0
            ? "\(succeeded)枚成功、\(failed)枚失敗"
            : "\(succeeded)枚の画像を生成しました"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func persistSucceededJobs(_ jobs: [GenerationJob], request: GenerationRequest, projectID: UUID) {
        let succeededCount = jobs.filter { $0.status == .succeeded }.count
        if succeededCount > 0 {
            totalGeneratedImages += succeededCount
        }

        if succeededCount > 0, let idx = projects.firstIndex(where: { $0.id == projectID }) {
            projects[idx].updatedAt = Date()
        }

        for job in jobs where job.status == .succeeded {
            let item = ProjectItem(
                projectID: projectID,
                prompt: job.prompt,
                revisedPrompt: job.revisedPrompt,
                aspectRatio: request.aspectRatio,
                errorMessage: job.errorMessage,
                editedFromItemID: request.editSource?.projectItemID
            )

            do {
                guard let imageData = job.imageData else { throw ImageCreatorError.missingGeneratedContent }
                try projectStore.writeItemData(imageData, for: item)
                items.append(item)
                if let img = NSImage(data: imageData) {
                    imageCache.setObject(img, forKey: item.fileURL(in: projectStore.rootDirectory) as NSURL)
                }
            } catch {
                logs.append("プロジェクトへの保存に失敗しました: \(error.localizedDescription)")
            }
        }

        saveState()
    }
}

// MARK: - Export types

enum ExportFormat: Int, CaseIterable {
    case png = 0, jpeg = 1, svg = 2

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .svg: return "SVG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .svg: return "svg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .svg: return .svg
        }
    }
}

@MainActor
final class ExportPanelController: NSObject {
    let panel: NSSavePanel
    let baseFilename: String
    private(set) var selectedFormat: ExportFormat = .png
    private let popUp: NSPopUpButton

    init(panel: NSSavePanel, baseFilename: String) {
        self.panel = panel
        self.baseFilename = baseFilename
        self.popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26), pullsDown: false)
        super.init()

        for fmt in ExportFormat.allCases {
            popUp.addItem(withTitle: fmt.displayName)
            popUp.lastItem?.tag = fmt.rawValue
        }
        popUp.selectItem(withTag: ExportFormat.png.rawValue)
        popUp.target = self
        popUp.action = #selector(onChange(_:))

        let label = NSTextField(labelWithString: "形式:")
        label.font = NSFont.systemFont(ofSize: 13)
        let stack = NSStackView(views: [label, popUp])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 42)

        panel.accessoryView = stack
        applyFormat(.png)
    }

    @objc private func onChange(_ sender: NSPopUpButton) {
        guard let fmt = ExportFormat(rawValue: sender.selectedTag()) else { return }
        selectedFormat = fmt
        applyFormat(fmt)
    }

    private func applyFormat(_ fmt: ExportFormat) {
        panel.allowedContentTypes = [fmt.contentType]
        let ext = fmt.fileExtension
        let stem = (baseFilename as NSString).pathExtension.isEmpty
            ? baseFilename
            : (baseFilename as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(stem).\(ext)"
    }
}

enum ImageEncoder {
    static func jpegData(fromPNG png: Data, quality: CGFloat = 0.92) throws -> Data {
        guard let source = NSImage(data: png) else { throw ExportError.encodeFailed }
        let size = source.size
        let composed = NSImage(size: size)
        composed.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        source.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0)
        composed.unlockFocus()
        guard
            let tiff = composed.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        else { throw ExportError.encodeFailed }
        return jpeg
    }

    static func svgWrapping(pngData: Data) throws -> Data {
        guard
            let img = NSImage(data: pngData),
            let rep = img.representations.first
        else { throw ExportError.encodeFailed }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        let base64 = pngData.base64EncodedString()
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <image href="data:image/png;base64,\(base64)" width="\(w)" height="\(h)"/>
        </svg>
        """
        guard let data = xml.data(using: .utf8) else { throw ExportError.encodeFailed }
        return data
    }
}

private enum ExportError: LocalizedError {
    case encodeFailed
    var errorDescription: String? { "エクスポートのエンコードに失敗しました。" }
}

enum ExportNaming {
    private static let invalidChars = CharacterSet(charactersIn: "/\\:?*\"<>|")
    private static let maxLength = 64

    static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = trimmed.unicodeScalars.map { scalar -> Character in
            invalidChars.contains(scalar) ? "_" : Character(scalar)
        }.reduce(into: "") { $0.append($1) }
        s = s.replacingOccurrences(of: " ", with: "_")
        if s.isEmpty { s = "Untitled" }
        if s.count > maxLength { s = String(s.prefix(maxLength)) }
        return s
    }

    static func baseFilename(forProjectName projectName: String, ordinal: Int) -> String {
        let safe = sanitize(projectName)
        return String(format: "%@-%02d", safe, ordinal)
    }
}
