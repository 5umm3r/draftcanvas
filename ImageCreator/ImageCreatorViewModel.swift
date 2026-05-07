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
    @Published var history: [GenerationHistoryItem] = []
    @Published var selectedJobID: UUID?
    @Published var selectedHistoryItemID: UUID?
    @Published var logs: [String] = []
    @Published var isGenerating = false
    @Published var accountUsageStatus = CodexAccountUsageStatus.unavailable
    @Published var isRefreshingAccountUsage = false
    @Published var preferredSaveFolder: URL?
    @Published var editSource: GenerationEditSource?

    private let client: CodexAppServerClient
    private let coordinator: GenerationCoordinator
    private let historyStore: GenerationHistoryStore
    private let preferredSaveFolderStore: PreferredSaveFolderStore

    init(
        historyStore: GenerationHistoryStore = GenerationHistoryStore(),
        preferredSaveFolderStore: PreferredSaveFolderStore = PreferredSaveFolderStore()
    ) {
        let client = CodexAppServerClient()
        self.client = client
        self.coordinator = GenerationCoordinator(runner: CodexGenerationRunner(client: client))
        self.historyStore = historyStore
        self.preferredSaveFolderStore = preferredSaveFolderStore
        client.onLog = { [weak self] message in
            Task { @MainActor in
                self?.logs.append(message)
            }
        }
        loadHistory()
        preferredSaveFolder = preferredSaveFolderStore.load()
        refreshAccountUsage()
    }

    var selectedJob: GenerationJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID }
    }

    var selectedHistoryItem: GenerationHistoryItem? {
        guard let selectedHistoryItemID else { return history.first }
        return history.first { $0.id == selectedHistoryItemID }
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

    func generate() {
        guard canGenerate else { return }

        let request = GenerationRequest(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            count: count,
            concurrency: concurrency,
            transparentBackground: transparentBackground,
            outputMode: outputMode,
            aspectRatio: aspectRatio,
            editSource: editSource
        )

        isGenerating = true
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")
        if let editSource {
            logs.append("履歴から再編集します: \(editSource.filePath)")
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
                self.isGenerating = false
                self.persistSucceededJobs(results, request: request)
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

    func saveSelected() {
        guard let job = selectedJob else { return }
        save(job: job)
    }

    func saveAll() {
        let completed = jobs.filter { $0.status == .succeeded }
        guard !completed.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "保存"
        panel.message = "生成結果を保存するフォルダを選択してください。"
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        for job in completed {
            do {
                let url = directory.appendingPathComponent(defaultFilename(for: job))
                try write(job: job, to: url)
                logs.append("保存しました: \(url.path)")
            } catch {
                logs.append("保存に失敗しました: \(error.localizedDescription)")
            }
        }
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

        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        do {
            try preferredSaveFolderStore.save(directory)
            preferredSaveFolder = directory
            logs.append("保存先フォルダを設定しました: \(directory.path)")
        } catch {
            logs.append("保存先フォルダの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    func edit(historyItem: GenerationHistoryItem) {
        let fileURL = historyItem.fileURL(in: historyStore.rootDirectory)
        var svgText: String?
        if historyItem.outputMode == .svg {
            svgText = try? String(contentsOf: fileURL, encoding: .utf8)
        }

        prompt = historyItem.prompt
        outputMode = historyItem.outputMode
        transparentBackground = historyItem.transparentBackground
        aspectRatio = historyItem.aspectRatio ?? .square
        editSource = GenerationEditSource(
            historyItemID: historyItem.id,
            filePath: fileURL.path,
            outputMode: historyItem.outputMode,
            originalPrompt: historyItem.prompt,
            svgText: svgText
        )
        logs.append("履歴を再編集対象にしました: \(fileURL.path)")
    }

    func cancelEditingHistoryItem() {
        editSource = nil
    }

    func reveal(historyItem: GenerationHistoryItem) {
        let fileURL = historyItem.fileURL(in: historyStore.rootDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func fileURL(for historyItem: GenerationHistoryItem) -> URL {
        historyItem.fileURL(in: historyStore.rootDirectory)
    }

    private func save(job: GenerationJob) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(for: job)
        panel.allowedContentTypes = job.svgText == nil ? [.png] : [.svg]
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try write(job: job, to: url)
            logs.append("保存しました: \(url.path)")
        } catch {
            logs.append("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    private func write(job: GenerationJob, to url: URL) throws {
        if let svgText = job.svgText {
            guard let data = svgText.data(using: .utf8) else {
                throw ImageCreatorError.svgExtractionFailed
            }
            try data.write(to: url, options: .atomic)
        } else if let imageData = job.imageData {
            try imageData.write(to: url, options: .atomic)
        } else {
            throw ImageCreatorError.missingGeneratedContent
        }
    }

    private func defaultFilename(for job: GenerationJob) -> String {
        let number = String(format: "%02d", job.index + 1)
        if job.svgText != nil {
            return "image-\(number).svg"
        }
        return "image-\(number).png"
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

    private func loadHistory() {
        do {
            history = try historyStore.load()
        } catch {
            history = []
            logs.append("履歴の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    private func persistSucceededJobs(_ jobs: [GenerationJob], request: GenerationRequest) {
        for job in jobs where job.status == .succeeded {
            do {
                let item = try historyStore.add(job: job, request: request)
                history.insert(item, at: 0)
            } catch {
                logs.append("履歴の保存に失敗しました: \(error.localizedDescription)")
            }
        }
    }
}
