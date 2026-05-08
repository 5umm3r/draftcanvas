import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageCreatorViewModel: ObservableObject {
    @Published var prompt = ""
    @Published var count = 4
    @Published var concurrency = 2
    @Published var transparentBackground = false
    @Published var outputMode: GenerationOutputMode = .raster
    @Published var aspectRatio: GenerationAspectRatio = .square
    @Published var jobs: [GenerationJob] = []
    @Published var projects: [Project] = []
    @Published var items: [ProjectItem] = []
    @Published var selectedProjectID: UUID? {
        didSet {
            guard selectedProjectID != oldValue, !isLoadingProjects else { return }
            saveState()
        }
    }
    @Published var selectedJobID: UUID?
    @Published var selectedItemID: UUID?
    @Published var logs: [String] = []
    @Published var isGenerating = false
    @Published var accountUsageStatus = CodexAccountUsageStatus.unavailable
    @Published var isRefreshingAccountUsage = false
    @Published var preferredSaveFolder: URL?
    @Published var editSource: GenerationEditSource?

    private let client: CodexAppServerClient
    private let coordinator: GenerationCoordinator
    private let projectStore: ProjectStore
    private let preferredSaveFolderStore: PreferredSaveFolderStore
    private var isLoadingProjects = false

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
        refreshAccountUsage()
    }

    // MARK: - Computed

    var selectedJob: GenerationJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID }
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
        editSource != nil
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(initialName: String? = nil) -> Project {
        let name = initialName ?? ProjectNaming.defaultName()
        let project = Project(name: name, isAutoNamed: true)
        projects.append(project)
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
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id  // didSet → saveState
        } else {
            saveState()
        }
    }

    func moveProject(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveState()
    }

    // MARK: - Generation

    func generate() {
        guard canGenerate else { return }

        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

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
            let newProject = createProject(initialName: ProjectNaming.summarize(promptText))
            targetProjectID = newProject.id
        }

        let request = GenerationRequest(
            prompt: promptText,
            count: count,
            concurrency: concurrency,
            transparentBackground: transparentBackground,
            outputMode: outputMode,
            aspectRatio: aspectRatio,
            editSource: editSource
        )

        jobs = []
        isGenerating = true
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")
        if let editSource {
            logs.append("アイテムを再編集します: \(editSource.filePath)")
        }

        Task {
            let results = await coordinator.run(request: request) { [weak self] job in
                await MainActor.run {
                    self?.upsert(job)
                }
            }

            await MainActor.run {
                self.jobs = results
                self.selectedJobID = results.first(where: { $0.status == .succeeded })?.id ?? results.first?.id
                self.persistSucceededJobs(results, request: request, projectID: targetProjectID)
                self.isGenerating = false
                self.editSource = nil
                self.logs.append("全ジョブが終了しました。")
                self.refreshAccountUsage()
            }
        }
    }

    func refreshAccountUsage() {
        guard !isRefreshingAccountUsage else { return }

        isRefreshingAccountUsage = true
        logs.append("Codexアカウントと使用量を取得します。")

        Task {
            do {
                let status = try await client.readAccountUsageStatus()
                await MainActor.run {
                    self.accountUsageStatus = status
                    self.isRefreshingAccountUsage = false
                    self.logs.append("Codexアカウントと使用量を更新しました。")
                }
            } catch {
                await MainActor.run {
                    self.accountUsageStatus = .unavailable
                    self.isRefreshingAccountUsage = false
                    self.logs.append("Codexアカウントと使用量の取得に失敗しました: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopServer() {
        client.stop()
        logs.append("codex app-server を停止しました。")
    }

    func cancelEditingHistoryItem() {
        editSource = nil
    }

    // MARK: - Item actions

    func edit(item: ProjectItem) {
        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        var svgText: String?
        if item.outputMode == .svg {
            svgText = try? String(contentsOf: fileURL, encoding: .utf8)
        }
        prompt = item.prompt
        outputMode = item.outputMode
        transparentBackground = item.transparentBackground
        aspectRatio = item.aspectRatio
        editSource = GenerationEditSource(
            projectItemID: item.id,
            filePath: fileURL.path,
            outputMode: item.outputMode,
            originalPrompt: item.prompt,
            svgText: svgText
        )
        logs.append("アイテムを再編集対象にしました: \(fileURL.path)")
    }

    func reveal(item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL(in: projectStore.rootDirectory)])
    }

    func fileURL(for item: ProjectItem) -> URL {
        item.fileURL(in: projectStore.rootDirectory)
    }

    func saveItem(_ item: ProjectItem) {
        let ext = item.fileExtension
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "image.\(ext)"
        panel.allowedContentTypes = ext == "svg" ? [.svg] : [.png]
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let src = item.fileURL(in: projectStore.rootDirectory)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            logs.append("保存しました: \(dest.path)")
        } catch {
            logs.append("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    func saveSelected() {
        guard let job = selectedJob else { return }
        saveJob(job)
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

    private func saveJob(_ job: GenerationJob) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(for: job)
        panel.allowedContentTypes = job.svgText == nil ? [.png] : [.svg]
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try write(job: job, to: url)
            logs.append("保存しました: \(url.path)")
        } catch {
            logs.append("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    private func write(job: GenerationJob, to url: URL) throws {
        if let svgText = job.svgText {
            guard let data = svgText.data(using: .utf8) else { throw ImageCreatorError.svgExtractionFailed }
            try data.write(to: url, options: .atomic)
        } else if let imageData = job.imageData {
            try imageData.write(to: url, options: .atomic)
        } else {
            throw ImageCreatorError.missingGeneratedContent
        }
    }

    private func defaultFilename(for job: GenerationJob) -> String {
        let number = String(format: "%02d", job.index + 1)
        return job.svgText != nil ? "image-\(number).svg" : "image-\(number).png"
    }

    private func upsert(_ job: GenerationJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        if selectedJobID == nil {
            selectedJobID = job.id
        }
    }

    private func loadProjects() {
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        let snapshot = projectStore.load()
        projects = snapshot.projects
        items = snapshot.items
        selectedProjectID = snapshot.selectedProjectID
    }

    private func saveState() {
        var snapshot = ProjectStore.Snapshot()
        snapshot.projects = projects
        snapshot.items = items
        snapshot.selectedProjectID = selectedProjectID
        projectStore.save(snapshot)
    }

    private func persistSucceededJobs(_ jobs: [GenerationJob], request: GenerationRequest, projectID: UUID) {
        let ext = request.outputMode == .raster ? "png" : "svg"

        for job in jobs where job.status == .succeeded {
            let item = ProjectItem(
                projectID: projectID,
                prompt: job.prompt,
                revisedPrompt: job.revisedPrompt,
                outputMode: request.outputMode,
                aspectRatio: request.aspectRatio,
                transparentBackground: request.transparentBackground,
                fileExtension: ext,
                errorMessage: job.errorMessage
            )

            do {
                switch request.outputMode {
                case .raster:
                    guard let imageData = job.imageData else { throw ImageCreatorError.missingGeneratedContent }
                    try projectStore.writeItemData(imageData, for: item)
                case .svg:
                    guard let svgText = job.svgText, let data = svgText.data(using: .utf8) else {
                        throw ImageCreatorError.svgExtractionFailed
                    }
                    try projectStore.writeItemData(data, for: item)
                }
                items.append(item)
            } catch {
                logs.append("プロジェクトへの保存に失敗しました: \(error.localizedDescription)")
            }
        }

        saveState()
    }
}
