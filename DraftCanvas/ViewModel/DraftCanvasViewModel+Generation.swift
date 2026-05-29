import AppKit
import Foundation
import UserNotifications

extension DraftCanvasViewModel {
    func generate(skipRateLimitCheck: Bool = false) {
        guard canGenerate else { return }
        guard !isGeneratingForSelected else { return }
        if accountUsageStatus.isChatGPTFreePlan {
            pendingFreeAccountBlock = true
            return
        }
        if currentInputs.model.isEmpty, let fallback = availableModels.first(where: \.isDefault)?.id ?? availableModels.first?.id {
            if let id = selectedProjectID {
                inputsByProject[id]?.model = fallback
            } else {
                draftInputs.model = fallback
            }
        }

        let inputs = currentInputs
        if !skipRateLimitCheck, checkRateLimitBeforeGenerate(inputs: inputs) { return }
        let promptText = inputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        // プロンプト履歴に記録
        if !promptText.isEmpty {
            recordPromptHistory(promptText)
        }

        let targetProjectID: UUID
        if let existing = selectedProjectID, projects.contains(where: { $0.id == existing }) {
            targetProjectID = existing
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
            attachedImagePath: inputs.attachedImage?.filePath,
            attachedImageKind: inputs.attachedImage?.kind ?? .regular,
            model: inputs.model,
            reasoningEffort: inputs.reasoningEffort,
            translateToEnglish: translateToEnglish
        )

        lastRequestByProject[targetProjectID] = request
        generatingProjectIDs.insert(targetProjectID)
        activityTracker.begin()
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")
        if let editSource = inputs.editSource {
            logs.append("アイテムを再編集します: \(editSource.filePath)")
        }

        let placeholderJobs = (0..<request.normalizedCount).map { index in
            GenerationJob(index: index, prompt: request.prompt, aspectRatio: request.aspectRatio)
        }
        for job in placeholderJobs {
            upsert(job, into: targetProjectID)
        }

        let runID = UUID()

        let generationTask = Task { [weak self] in
            guard let self else { return }
            let preparedRequest = await prepareRequestForGeneration(request)
            await MainActor.run {
                self.lastRequestByProject[targetProjectID] = preparedRequest
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.finishRun(runID: runID, projectID: targetProjectID)
                }
                return
            }

            let results = await coordinator.runSpecific(jobs: placeholderJobs, request: preparedRequest) { [weak self] job in
                await MainActor.run {
                    guard let self else { return }
                    self.handleJobUpdate(job, into: targetProjectID, request: preparedRequest)
                }
            }

            await MainActor.run {
                self.finishRun(runID: runID, projectID: targetProjectID, results: results)
                if var inputs = self.inputsByProject[targetProjectID] {
                    if let editSource = inputs.editSource, editSource.isInpainting {
                        self.projectStore.cleanupMaskFiles(id: editSource.projectItemID)
                    }
                    inputs.editSource = nil
                    if let attached = inputs.attachedImage {
                        self.projectStore.cleanupAttachment(id: attached.id)
                    }
                    inputs.attachedImage = nil
                    self.inputsByProject[targetProjectID] = inputs
                }
                self.activeEditProjectID = nil
                self.logs.append("全ジョブが終了しました。")
                self.refreshAccountUsage()
            }
        }
        if generationTasks[targetProjectID] == nil {
            generationTasks[targetProjectID] = [:]
        }
        generationTasks[targetProjectID]?[runID] = generationTask
    }

    func prepareRequestForGeneration(_ request: GenerationRequest) async -> GenerationRequest {
        guard request.translateToEnglish else { return request }
        guard request.normalizedGenerationBrief == nil else { return request }
        guard !availableModels.isEmpty else { return request }

        do {
            let model = Self.selectFastLowCostModel(from: availableModels)
            let normalized = try await PromptLanguageNormalizer.normalize(
                request: request,
                client: client,
                model: model
            )
            guard !normalized.isEmpty else { return request }
            var prepared = request
            prepared.normalizedPrompt = normalized
            logs.append("生成指示を英語に正規化しました。")
            return prepared
        } catch {
            logs.append("生成指示の英語正規化に失敗したため元のプロンプトで続行します: \(error.localizedDescription)")
            return request
        }
    }

    func upsert(_ job: GenerationJob, into projectID: UUID) {
        var jobs = jobsByProject[projectID] ?? []
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        jobsByProject[projectID] = jobs
    }

    func handleJobUpdate(_ job: GenerationJob, into projectID: UUID, request: GenerationRequest) {
        if job.status == .succeeded {
            persistAndPromoteSucceededJob(job, request: request, projectID: projectID)
        } else {
            if job.isFreeAccountBlocked {
                pendingFreeAccountBlock = true
            }
            upsert(job, into: projectID)
        }
    }

    private func persistAndPromoteSucceededJob(_ job: GenerationJob, request: GenerationRequest, projectID: UUID) {
        let actualRatio = job.imageData.flatMap { pixelAspectRatioFromImageData($0) }
        var item = ProjectItem(
            projectID: projectID,
            prompt: job.prompt,
            revisedPrompt: job.revisedPrompt,
            aspectRatio: request.aspectRatio,
            actualAspectRatio: actualRatio,
            errorMessage: nil,
            editedFromItemID: request.editSource?.projectItemID
        )
        do {
            guard let imageData = job.imageData else { throw DraftCanvasError.missingGeneratedContent }
            if request.attachedImageKind == .sketch, let sketchPath = request.attachedImagePath {
                let saved = try projectStore.saveSketchSource(from: sketchPath, itemID: item.id)
                item.sketchSourcePath = saved.path
            }
            try projectStore.writeItemData(imageData, for: item)
            items.append(item)
            thumbnailStore.writeThumbnail(from: imageData, item: item)

            if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].updatedAt = Date()
            }

            if var jobs = jobsByProject[projectID] {
                jobs.removeAll { $0.id == job.id }
                jobsByProject[projectID] = jobs
            }

            if selectedJobID == job.id {
                selectedItemID = item.id
                selectedJobID = nil
            }

            saveState()
        } catch {
            logs.append("プロジェクトへの保存に失敗しました: \(error.localizedDescription)")
            var failedJob = job
            failedJob.status = .failed
            failedJob.errorMessage = error.localizedDescription
            upsert(failedJob, into: projectID)
        }
    }

    func onAllJobsCompleted(results: [GenerationJob]) {
        if completionSound != CompletionSoundOption.off.rawValue {
            NSSound(named: NSSound.Name(completionSound))?.play()
        }
        let succeeded = results.filter { $0.status == .succeeded }.count
        let failed = results.filter { $0.status == .failed }.count
        sendCompletionNotification(succeeded: succeeded, failed: failed)
    }

    func sendCompletionNotification(succeeded: Int, failed: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "画像生成完了")
        content.body = failed > 0
            ? String(localized: "\(succeeded)枚成功、\(failed)枚失敗")
            : String(localized: "\(succeeded)枚の画像を生成しました")
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func retryFailedJobs(projectID: UUID) {
        guard !isGenerating(for: projectID),
              let request = lastRequestByProject[projectID] else { return }

        var failedJobs = (jobsByProject[projectID] ?? []).filter { $0.status == .failed }
        guard !failedJobs.isEmpty else { return }

        dismissedFailedJobIDs.subtract(failedJobs.map(\.id))

        for i in failedJobs.indices {
            failedJobs[i].status = .queued
            failedJobs[i].errorMessage = nil
            failedJobs[i].logs = []
            failedJobs[i].imageData = nil
            failedJobs[i].hitRateLimitDuringRun = false
            failedJobs[i].failureKind = nil
        }
        for job in failedJobs {
            upsert(job, into: projectID)
        }

        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("失敗ジョブを再試行します: \(failedJobs.count)件")

        let runID = UUID()

        let retryTask = Task { [weak self] in
            guard let self else { return }
            let preparedRequest = await prepareRequestForGeneration(request)
            await MainActor.run {
                self.lastRequestByProject[projectID] = preparedRequest
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.finishRun(runID: runID, projectID: projectID)
                }
                return
            }

            let retried = await coordinator.runSpecific(jobs: failedJobs, request: preparedRequest) { [weak self] job in
                await MainActor.run {
                    guard let self else { return }
                    self.handleJobUpdate(job, into: projectID, request: preparedRequest)
                }
            }

            await MainActor.run {
                self.finishRun(runID: runID, projectID: projectID, results: retried)
                self.refreshAccountUsage()
                self.logs.append("再試行完了。")
            }
        }
        if generationTasks[projectID] == nil {
            generationTasks[projectID] = [:]
        }
        generationTasks[projectID]?[runID] = retryTask
    }

    func cancelProjectRuns(projectID: UUID) {
        let tasks = generationTasks[projectID] ?? [:]
        for (_, task) in tasks { task.cancel() }
        generationTasks[projectID] = nil
        // バックオフ中の自動リトライも停止
        autoRetryTasks[projectID]?.cancel()
        autoRetryTasks.removeValue(forKey: projectID)
        autoRetryCountByProject.removeValue(forKey: projectID)
        if generatingProjectIDs.remove(projectID) != nil {
            activityTracker.end()
        }
    }

    private func finishRun(runID: UUID, projectID: UUID, results: [GenerationJob]? = nil) {
        generationTasks[projectID]?.removeValue(forKey: runID)
        if generationTasks[projectID]?.isEmpty == true {
            generationTasks.removeValue(forKey: projectID)
            generatingProjectIDs.remove(projectID)
            activityTracker.end()
        }
        if generatingProjectIDs.isEmpty {
            if needsAccountUsageRefreshAfterGeneration {
                needsAccountUsageRefreshAfterGeneration = false
                refreshAccountUsage()
            }
            if let results {
                // 自動リトライ判定
                let autoRetryTargets = results.filter {
                    $0.status == .failed && ($0.failureKind == .rateLimited || $0.failureKind == .timeout)
                }
                let retryCount = autoRetryCountByProject[projectID] ?? 0
                if autoRetryEnabled, !autoRetryTargets.isEmpty, retryCount < 3 {
                    autoRetryCountByProject[projectID] = retryCount + 1
                    let attempt = retryCount + 1
                    let delay = pow(2.0, Double(attempt)) * 5.0  // 10s, 20s, 40s
                    logs.append("自動再試行を\(Int(delay))秒後に実行します（\(attempt)/3回目）")
                    let retryTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        await MainActor.run { [weak self] in
                            self?.autoRetryTasks.removeValue(forKey: projectID)
                            self?.autoRetryFailedJobs(projectID: projectID)
                        }
                    }
                    autoRetryTasks[projectID] = retryTask
                    return  // 自動リトライが終わるまで onAllJobsCompleted を保留
                }
                // 自動リトライなし / 上限到達 → カウントリセットして完了通知
                autoRetryCountByProject.removeValue(forKey: projectID)
                onAllJobsCompleted(results: results)
            }
        }
    }

    private func autoRetryFailedJobs(projectID: UUID) {
        guard !isGenerating(for: projectID),
              let request = lastRequestByProject[projectID] else { return }

        var failedJobs = (jobsByProject[projectID] ?? []).filter {
            $0.status == .failed && ($0.failureKind == .rateLimited || $0.failureKind == .timeout)
        }
        guard !failedJobs.isEmpty else {
            autoRetryCountByProject.removeValue(forKey: projectID)
            return
        }

        // ジョブ状態をリセット（dismissedFailedJobIDs は変更しない）
        for i in failedJobs.indices {
            failedJobs[i].status = .queued
            failedJobs[i].errorMessage = nil
            failedJobs[i].logs = []
            failedJobs[i].imageData = nil
            failedJobs[i].hitRateLimitDuringRun = false
            failedJobs[i].failureKind = nil
        }
        for job in failedJobs {
            upsert(job, into: projectID)
        }

        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("自動再試行を開始します: \(failedJobs.count)件")

        let runID = UUID()
        let retryTask = Task { [weak self] in
            guard let self else { return }
            let preparedRequest = await prepareRequestForGeneration(request)
            await MainActor.run { self.lastRequestByProject[projectID] = preparedRequest }

            guard !Task.isCancelled else {
                await MainActor.run { self.finishRun(runID: runID, projectID: projectID) }
                return
            }

            let retried = await coordinator.runSpecific(
                jobs: failedJobs,
                request: preparedRequest
            ) { [weak self] job in
                await MainActor.run {
                    self?.handleJobUpdate(job, into: projectID, request: preparedRequest)
                }
            }
            await MainActor.run {
                self.finishRun(runID: runID, projectID: projectID, results: retried)
                self.refreshAccountUsage()
                self.logs.append("自動再試行完了。")
            }
        }
        if generationTasks[projectID] == nil { generationTasks[projectID] = [:] }
        generationTasks[projectID]?[runID] = retryTask
    }

    private func isGenerating(for projectID: UUID) -> Bool {
        generatingProjectIDs.contains(projectID)
    }

    private func checkRateLimitBeforeGenerate(inputs: ProjectInputs) -> Bool {
        guard accountUsageStatus.accountKind == .chatgpt else { return false }

        let needsRefresh = accountUsageStatusFetchedAt.map {
            Date().timeIntervalSince($0) > 30
        } ?? true

        if needsRefresh {
            refreshAccountUsage()
            return false
        }

        guard let remaining = accountUsageStatus.primaryUsageRemainingFraction else { return false }
        let normalizedCount = min(max(inputs.count, 1), 24)
        let normalizedConcurrency = min(max(inputs.concurrency, 1), normalizedCount)
        let threshold = Double(normalizedConcurrency) * 0.05
        guard remaining < threshold else { return false }

        let percent = Int((remaining * 100).rounded())
        pendingRateLimitConfirmation = RateLimitConfirmation(
            remainingPercent: percent,
            concurrency: normalizedConcurrency,
            resume: { [weak self] in
                self?.pendingRateLimitConfirmation = nil
                self?.generate(skipRateLimitCheck: true)
            }
        )
        return true
    }
}
