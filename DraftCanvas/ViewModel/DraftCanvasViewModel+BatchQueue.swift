import AppKit
import Foundation

extension DraftCanvasViewModel {
    /// 複数プロンプトをキューに追加（空行は無視）
    func enqueueBatch(prompts: [String], count: Int) {
        let entries = prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BatchQueueEntry(prompt: $0, count: count) }
        guard !entries.isEmpty else { return }
        batchQueue.append(contentsOf: entries)
        if !isBatchRunning {
            startBatchQueue()
        }
    }

    func startBatchQueue() {
        guard !isBatchRunning else { return }
        guard canGenerate else { return }
        if accountUsageStatus.isChatGPTFreePlan {
            pendingFreeAccountBlock = true
            return
        }
        isBatchRunning = true
        dispatchNextBatchEntry()
    }

    func cancelBatchQueue() {
        // 待機中のみクリア。実行中ジョブは生成側のキャンセルに従う
        batchQueue.removeAll { $0.status == .queued }
        isBatchRunning = false
    }

    func dispatchNextBatchEntry() {
        // 次の queued エントリを探す
        guard let idx = batchQueue.firstIndex(where: { $0.status == .queued }) else {
            // 全消化完了
            isBatchRunning = false
            logs.append("バッチキューが完了しました。")
            // バッチ全体完了時にまとめて完了音を鳴らす
            if completionSound != CompletionSoundOption.off.rawValue {
                NSSound(named: NSSound.Name(completionSound))?.play()
            }
            return
        }

        batchQueue[idx].status = .running
        let entry = batchQueue[idx]

        // 各エントリは新規プロジェクトを作る（generate() と同じ命名ロジック）
        let newProject = createProject(initialName: ProjectNaming.summarize(entry.prompt), resetInputs: false)
        let projectID = newProject.id

        let model = currentInputs.model.isEmpty
            ? (availableModels.first(where: \.isDefault)?.id ?? availableModels.first?.id ?? "")
            : currentInputs.model

        let request = GenerationRequest(
            prompt: entry.prompt,
            count: entry.count,
            concurrency: min(entry.count, currentInputs.concurrency),
            aspectRatio: currentInputs.aspectRatio,
            model: model,
            reasoningEffort: currentInputs.reasoningEffort,
            translateToEnglish: translateToEnglish
        )

        recordPromptHistory(entry.prompt)

        let jobs = (0..<request.normalizedCount).map { index in
            GenerationJob(index: index, prompt: request.prompt, aspectRatio: request.aspectRatio)
        }

        runGeneration(request: request, projectID: projectID, jobs: jobs) { [weak self] in
            guard let self else { return }
            // エントリ完了 → ステータス更新 → 次へ
            if let i = self.batchQueue.firstIndex(where: { $0.id == entry.id }) {
                let projectFailed = (self.jobsByProject[projectID] ?? []).contains { $0.status == .failed }
                self.batchQueue[i].status = projectFailed ? .failed : .done
            }
            self.dispatchNextBatchEntry()
        }
    }
}
