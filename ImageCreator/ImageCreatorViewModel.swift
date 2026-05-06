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
    @Published var jobs: [GenerationJob] = []
    @Published var selectedJobID: UUID?
    @Published var logs: [String] = []
    @Published var isGenerating = false
    @Published var accountUsageStatus = CodexAccountUsageStatus.unavailable
    @Published var isRefreshingAccountUsage = false

    private let client: CodexAppServerClient
    private let coordinator: GenerationCoordinator

    init() {
        let client = CodexAppServerClient()
        self.client = client
        self.coordinator = GenerationCoordinator(runner: CodexGenerationRunner(client: client))
        client.onLog = { [weak self] message in
            Task { @MainActor in
                self?.logs.append(message)
            }
        }
        refreshAccountUsage()
    }

    var selectedJob: GenerationJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID }
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
            outputMode: outputMode
        )

        isGenerating = true
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")

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

    private func save(job: GenerationJob) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(for: job)
        panel.allowedContentTypes = job.svgText == nil ? [.png] : [.svg]

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
        switch outputMode {
        case .raster:
            return "image-\(number).png"
        case .svg:
            return "image-\(number).svg"
        }
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
}
