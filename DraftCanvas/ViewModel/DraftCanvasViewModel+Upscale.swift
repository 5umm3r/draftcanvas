import Foundation

extension DraftCanvasViewModel {

    func upscaleItem(_ item: ProjectItem) {
        let projectID = selectedProjectID ?? item.projectID
        guard !upscalingItemIDs.contains(item.id) else { return }
        upscalingItemIDs.insert(item.id)

        let label = item.prompt.prefix(30).isEmpty ? String(localized: "素材") : String(item.prompt.prefix(30))
        let job = GenerationJob(
            index: jobsByProject[projectID]?.count ?? 0,
            prompt: "高解像度化: \(label)",
            aspectRatio: item.aspectRatio
        )
        upsert(job, into: projectID)

        let fileURL = projectStore.resolvedFileURL(for: item)
        let itemID = item.id
        let clientRef = client
        let availableModelsRef = availableModels
        let translateToEnglishRef = translateToEnglish

        let task = Task { @MainActor in
            var running = job
            running.status = .running
            upsert(running, into: projectID)

            do {
                let originalData = try Data(contentsOf: fileURL)

                let upscaledData: Data = try await Task.detached(priority: .userInitiated) {
                    try await Self.runUpscaleTurn(
                        client: clientRef,
                        availableModels: availableModelsRef,
                        item: item,
                        fileURL: fileURL,
                        translateToEnglish: translateToEnglishRef
                    )
                }.value

                var succeeded = running
                succeeded.status = .succeeded
                upsert(succeeded, into: projectID)
                upscalingItemIDs.remove(itemID)
                upscalingTasks.removeValue(forKey: itemID)
                upscalePreview = UpscalePreviewPayload(
                    originalItem: item,
                    originalImageData: originalData,
                    upscaledImageData: upscaledData,
                    jobLogs: succeeded.logs
                )
                logs.append("高解像度化プレビュー準備完了: \(itemID)")
            } catch {
                upscalingItemIDs.remove(itemID)
                upscalingTasks.removeValue(forKey: itemID)
                guard !(error is CancellationError) else { return }
                var failed = running
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                upsert(failed, into: projectID)
                errorToast = String(localized: "高解像度化に失敗しました")
                logs.append("高解像度化失敗: \(error.localizedDescription)")
            }
        }
        upscalingTasks[item.id] = task
    }

    func cancelUpscale(itemID: UUID) {
        upscalingTasks[itemID]?.cancel()
        upscalingTasks.removeValue(forKey: itemID)
        upscalingItemIDs.remove(itemID)
    }

    func commitUpscale(payload: UpscalePreviewPayload, mode: UpscaleApplyMode) {
        upscalePreview = nil
        let item = payload.originalItem
        let projectID = selectedProjectID ?? item.projectID
        let data = payload.upscaledImageData

        switch mode {
        case .discard:
            return

        case .addAsNew:
            let aspectRatio = aspectRatioFromImageData(data)
            let newItem = ProjectItem(
                projectID: projectID,
                prompt: item.prompt,
                revisedPrompt: item.revisedPrompt,
                aspectRatio: aspectRatio,
                editedFromItemID: item.id
            )
            do {
                try projectStore.writeItemData(data, for: newItem)
                thumbnailStore.writeThumbnail(from: data, item: newItem)
                items.append(newItem)
                if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                    projects[idx].updatedAt = Date()
                }
                saveState()
                logs.append("高解像度化: 新規アイテム追加 \(newItem.id)")
            } catch {
                errorToast = String(localized: "高解像度化結果の保存に失敗しました")
                logs.append("高解像度化保存失敗: \(error.localizedDescription)")
            }

        case .overwrite:
            let origURL = projectStore.resolvedFileURL(for: item)
            do {
                try projectStore.writeItemData(data, for: item)
                thumbnailStore.deleteThumbnail(for: item)
                thumbnailStore.writeThumbnail(from: data, item: item)
                originalImageStore.evict(url: origURL)
                thumbnailStore.invalidate()
                if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                    projects[idx].updatedAt = Date()
                }
                saveState()
                logs.append("高解像度化: 上書き完了 \(item.id)")
            } catch {
                errorToast = String(localized: "高解像度化結果の上書きに失敗しました")
                logs.append("高解像度化上書き失敗: \(error.localizedDescription)")
            }
        }
    }

    private static func runUpscaleTurn(
        client: CodexAppServerClient,
        availableModels: [CodexModel],
        item: ProjectItem,
        fileURL: URL,
        translateToEnglish: Bool
    ) async throws -> Data {
        try await client.start()
        let model = selectFastLowCostModel(from: availableModels)
        let description = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "imported asset"
            : item.prompt
        let normalizedDescription: String?
        if translateToEnglish {
            normalizedDescription = try? await PromptLanguageNormalizer.normalizeUpscaleDescription(
                description,
                client: client,
                model: model
            )
        } else {
            normalizedDescription = nil
        }
        let threadID = try await client.startThread(
            model: model.id,
            reasoningEffort: model.defaultReasoningEffort
        )
        let prompt = PromptFactory.upscalePrompt(
            for: item,
            translateToEnglish: translateToEnglish,
            normalizedDescription: normalizedDescription
        )
        let result = try await client.runTurn(
            threadID: threadID,
            prompt: prompt,
            referenceImagePath: fileURL.path
        )
        guard let imageResult = result.imageResult else {
            throw DraftCanvasError.missingGeneratedContent
        }
        return imageResult.data
    }
}
