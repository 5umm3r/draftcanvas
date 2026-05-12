import AppKit
import Foundation
import UserNotifications

extension DraftCanvasViewModel {
    func generate() {
        guard canGenerate else { return }
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
                    if let attached = inputs.attachedImage {
                        self.projectStore.cleanupAttachment(id: attached.id)
                    }
                    inputs.attachedImage = nil
                    self.inputsByProject[targetProjectID] = inputs
                }
                self.logs.append("全ジョブが終了しました。")
                self.refreshAccountUsage()
            }
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

    func persistSucceededJobs(_ jobs: [GenerationJob], request: GenerationRequest, projectID: UUID) {
        let succeededCount = jobs.filter { $0.status == .succeeded }.count
        if succeededCount > 0 {
            totalGeneratedImages += succeededCount
            session5hCount += succeededCount
            sessionWeeklyCount += succeededCount
            pendingFiveHDelta += succeededCount
            pendingWeeklyDelta += succeededCount
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
                guard let imageData = job.imageData else { throw DraftCanvasError.missingGeneratedContent }
                try projectStore.writeItemData(imageData, for: item)
                self.items.append(item)
                if let img = NSImage(data: imageData) {
                    imageCache.setObject(img, forKey: item.fileURL(in: projectStore.rootDirectory) as NSURL, cost: img.estimatedBytes)
                }
                thumbnailStore.writeThumbnail(from: imageData, item: item)
            } catch {
                logs.append("プロジェクトへの保存に失敗しました: \(error.localizedDescription)")
            }
        }

        saveState()
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
}
