import AppKit
import Foundation
import UserNotifications

extension DraftCanvasViewModel {
    func generate(skipRateLimitCheck: Bool = false) {
        guard canGenerate else { return }
        if currentInputs.editSource != nil {
            guard !isGeneratingForSelected else { return }
        }
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
        recordHistory(prompt: promptText)

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

        if let editSource = inputs.editSource {
            logs.append("アイテムを再編集します: \(editSource.filePath)")
        }

        let placeholderJobs = (0..<request.normalizedCount).map { index in
            GenerationJob(index: index, prompt: request.prompt, aspectRatio: request.aspectRatio)
        }

        runGeneration(request: request, projectID: targetProjectID, jobs: placeholderJobs) { [weak self] in
            guard let self else { return }
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
        }
    }

    func runGeneration(
        request: GenerationRequest,
        projectID: UUID,
        jobs: [GenerationJob],
        onCompletion: (() -> Void)? = nil
    ) {
        lastRequestByProject[projectID] = request
        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("生成を開始しました。count=\(request.normalizedCount), concurrency=\(request.normalizedConcurrency)")

        let runID = UUID()
        let batchBase = Date()
        var taggedJobs = jobs
        for i in taggedJobs.indices {
            taggedJobs[i].runID = runID
            taggedJobs[i].scheduledAt = batchBase.addingTimeInterval(Double(taggedJobs[i].index) * 0.001)
        }
        for job in taggedJobs {
            upsert(job, into: projectID)
        }

        let generationTask = Task { [weak self] in
            guard let self else { return }
            let preparedRequest = await prepareRequestForGeneration(request)
            await MainActor.run {
                self.lastRequestByProject[projectID] = preparedRequest
                self.preparedRequestByRun[runID] = preparedRequest
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.finishRun(runID: runID, projectID: projectID)
                    onCompletion?()
                }
                return
            }

            let results = await coordinator.runSpecific(jobs: taggedJobs, request: preparedRequest) { [weak self] job in
                await MainActor.run {
                    guard let self else { return }
                    self.handleJobUpdate(job, into: projectID, request: preparedRequest)
                }
            }

            await MainActor.run {
                self.finishRun(runID: runID, projectID: projectID, results: results)
                onCompletion?()
                self.logs.append("全ジョブが終了しました。")
                self.refreshAccountUsage()
            }
        }
        if generationTasks[projectID] == nil {
            generationTasks[projectID] = [:]
        }
        generationTasks[projectID]?[runID] = generationTask
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
        if let runID = job.runID, generationTasks[projectID]?[runID] == nil {
            return
        }
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
            createdAt: job.scheduledAt,
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
        guard !isGenerating(for: projectID) else { return }

        let failedJobs = (jobsByProject[projectID] ?? []).filter { $0.status == .failed }
        guard !failedJobs.isEmpty else { return }

        dismissedFailedJobIDs.subtract(failedJobs.map(\.id))

        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("失敗ジョブを再試行します: \(failedJobs.count)件")

        let grouped = Dictionary(grouping: failedJobs, by: { $0.runID })
        var enqueued = false
        for (origRunID, groupJobs) in grouped {
            guard let request = origRunID.flatMap({ preparedRequestByRun[$0] })
                    ?? lastRequestByProject[projectID] else { continue }
            enqueueRetryRun(jobs: groupJobs, request: request, projectID: projectID, logMessage: "再試行完了。")
            enqueued = true
        }
        if !enqueued {
            generatingProjectIDs.remove(projectID)
            activityTracker.end()
        }
    }

    func cancelProjectRuns(projectID: UUID) {
        let tasks = generationTasks[projectID] ?? [:]
        let cancelledRunIDs = Set(tasks.keys)
        for (runID, task) in tasks {
            task.cancel()
            preparedRequestByRun.removeValue(forKey: runID)
        }
        generationTasks[projectID] = nil

        if var jobs = jobsByProject[projectID] {
            jobs.removeAll { job in
                guard let runID = job.runID else { return false }
                return cancelledRunIDs.contains(runID)
            }
            if jobs.isEmpty {
                jobsByProject.removeValue(forKey: projectID)
            } else {
                jobsByProject[projectID] = jobs
            }
        }

        autoRetryTasks[projectID]?.cancel()
        autoRetryTasks.removeValue(forKey: projectID)
        autoRetryCountByProject.removeValue(forKey: projectID)
        autoRetryRequestByProject.removeValue(forKey: projectID)
        if generatingProjectIDs.remove(projectID) != nil {
            activityTracker.end()
        }
        refreshAccountUsage()
    }

    func finishRun(runID: UUID, projectID: UUID, results: [GenerationJob]? = nil) {
        generationTasks[projectID]?.removeValue(forKey: runID)
        preparedRequestByRun.removeValue(forKey: runID)
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
                    let retryGrouped = Dictionary(grouping: autoRetryTargets, by: { $0.runID })
                    for (origRunID, _) in retryGrouped {
                        guard let rid = origRunID, let req = preparedRequestByRun[rid] else { continue }
                        if autoRetryRequestByProject[projectID] == nil {
                            autoRetryRequestByProject[projectID] = [:]
                        }
                        autoRetryRequestByProject[projectID]?[rid] = req
                    }
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
        guard !isGenerating(for: projectID) else {
            autoRetryCountByProject.removeValue(forKey: projectID)
            return
        }

        let failedJobs = (jobsByProject[projectID] ?? []).filter {
            $0.status == .failed && ($0.failureKind == .rateLimited || $0.failureKind == .timeout)
        }
        guard !failedJobs.isEmpty else {
            autoRetryCountByProject.removeValue(forKey: projectID)
            return
        }

        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("自動再試行を開始します: \(failedJobs.count)件")

        let grouped = Dictionary(grouping: failedJobs, by: { $0.runID })
        var enqueued = false
        for (origRunID, groupJobs) in grouped {
            guard let request = origRunID.flatMap({ autoRetryRequestByProject[projectID]?[$0] })
                    ?? lastRequestByProject[projectID] else { continue }
            enqueueRetryRun(jobs: groupJobs, request: request, projectID: projectID, logMessage: "自動再試行完了。")
            enqueued = true
        }
        autoRetryRequestByProject.removeValue(forKey: projectID)
        if !enqueued {
            generatingProjectIDs.remove(projectID)
            activityTracker.end()
        }
    }

    private func enqueueRetryRun(
        jobs: [GenerationJob],
        request: GenerationRequest,
        projectID: UUID,
        logMessage: String
    ) {
        var retryJobs = jobs
        for i in retryJobs.indices {
            retryJobs[i].status = .queued
            retryJobs[i].errorMessage = nil
            retryJobs[i].logs = []
            retryJobs[i].imageData = nil
            retryJobs[i].hitRateLimitDuringRun = false
            retryJobs[i].failureKind = nil
        }
        for job in retryJobs {
            upsert(job, into: projectID)
        }

        let runID = UUID()
        let retryTask = Task { [weak self] in
            guard let self else { return }
            let preparedRequest = await prepareRequestForGeneration(request)
            await MainActor.run {
                self.preparedRequestByRun[runID] = preparedRequest
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.finishRun(runID: runID, projectID: projectID) }
                return
            }

            let retried = await coordinator.runSpecific(jobs: retryJobs, request: preparedRequest) { [weak self] job in
                await MainActor.run {
                    self?.handleJobUpdate(job, into: projectID, request: preparedRequest)
                }
            }
            await MainActor.run {
                self.finishRun(runID: runID, projectID: projectID, results: retried)
                self.refreshAccountUsage()
                self.logs.append(logMessage)
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
