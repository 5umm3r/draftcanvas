import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImageCreatorViewModel: ObservableObject {
    // MARK: - Per-project state
    @Published var inputsByProject: [UUID: ProjectInputs] = [:]
    @Published var jobsByProject: [UUID: [GenerationJob]] = [:]
    @Published var generatingProjectIDs: Set<UUID> = []
    @Published var draftInputs: ProjectInputs = ProjectInputs()

    // MARK: - Global state
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
                } else {
                    self.draftInputs[keyPath: keyPath] = newValue
                }
            }
        )
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

    func moveProject(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveState()
    }

    // MARK: - Generation

    func generate() {
        guard canGenerate else { return }

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
            editSource: inputs.editSource
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
                if var inputs = self.inputsByProject[targetProjectID] {
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
        guard let id = selectedProjectID else { return }
        var inputs = inputsByProject[id] ?? ProjectInputs()
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
        logs.append("アイテムを再編集対象にしました: \(fileURL.path)")
    }

    func reveal(item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL(in: projectStore.rootDirectory)])
    }

    func fileURL(for item: ProjectItem) -> URL {
        item.fileURL(in: projectStore.rootDirectory)
    }

    func exportItem(_ item: ProjectItem) {
        guard let project = projects.first(where: { $0.id == item.projectID }) else { return }
        let ordinal = ordinalForItem(item, in: item.projectID)
        let base = ExportNaming.baseFilename(forProjectName: project.name, ordinal: ordinal)
        runExportPanel(baseFilename: base) { [weak self] dest, format in
            guard let self else { return }
            let pngData = try Data(contentsOf: item.fileURL(in: self.projectStore.rootDirectory))
            try self.writeExport(pngData: pngData, to: dest, format: format)
        }
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
        if selectedProjectID == projectID && selectedJobID == nil {
            selectedJobID = job.id
        }
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

    private func writeExport(pngData: Data, to url: URL, format: ExportFormat) throws {
        let data: Data
        switch format {
        case .png:
            data = pngData
        case .jpeg:
            data = try ImageEncoder.jpegData(fromPNG: pngData)
        case .svg:
            data = try ImageEncoder.svgWrapping(pngData: pngData)
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
            inputsByProject[project.id] = ProjectInputs()
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

    private func persistSucceededJobs(_ jobs: [GenerationJob], request: GenerationRequest, projectID: UUID) {
        for job in jobs where job.status == .succeeded {
            let item = ProjectItem(
                projectID: projectID,
                prompt: job.prompt,
                revisedPrompt: job.revisedPrompt,
                aspectRatio: request.aspectRatio,
                errorMessage: job.errorMessage
            )

            do {
                guard let imageData = job.imageData else { throw ImageCreatorError.missingGeneratedContent }
                try projectStore.writeItemData(imageData, for: item)
                items.append(item)
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
        case .svg: return "SVG (PNG埋め込み)"
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
