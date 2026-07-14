import Foundation

extension DraftCanvasViewModel {

    private static var upscaleModelDefaultsKey: String { "upscaleModel" }

    static var preferredUpscaleModel: UpscaleModel {
        let stored = UserDefaults.standard.string(forKey: upscaleModelDefaultsKey)
        return stored.flatMap(UpscaleModel.init(rawValue:)) ?? .general
    }

    static func savePreferredUpscaleModel(_ model: UpscaleModel) {
        UserDefaults.standard.set(model.rawValue, forKey: upscaleModelDefaultsKey)
    }

    func upscaleItem(_ item: ProjectItem) {
        upscaleItem(item, model: Self.preferredUpscaleModel)
    }

    func upscaleItem(_ item: ProjectItem, model: UpscaleModel) {
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
        upscalingJobContexts[item.id] = (job.id, projectID)

        let fileURL = projectStore.resolvedFileURL(for: item)
        let itemID = item.id

        let runToken = UUID()
        upscalingRunTokens[item.id] = runToken

        let task = Task { @MainActor in
            var running = job
            running.status = .running
            upsert(running, into: projectID)

            do {
                let originalData = try await imageLoader.loadData(at: fileURL, syncMonitor: syncMonitor)
                await cacheEviction.recordAccess(url: fileURL)

                let upscaledData = try await Self.runLocalUpscale(fileURL: fileURL, model: model)

                removeJob(id: job.id, from: projectID)
                // キャンセル後の再実行と競合しないよう、自分がまだ現行世代か確認する
                guard upscalingRunTokens[itemID] == runToken else { return }
                upscalingItemIDs.remove(itemID)
                upscalingTasks.removeValue(forKey: itemID)
                upscalingJobContexts.removeValue(forKey: itemID)
                upscalingRunTokens.removeValue(forKey: itemID)
                upscalePreview = UpscalePreviewPayload(
                    originalItem: item,
                    originalImageData: originalData,
                    upscaledImageData: upscaledData,
                    model: model,
                    jobLogs: running.logs
                )
                logs.append("高解像度化プレビュー準備完了: \(itemID)")
            } catch {
                removeJob(id: job.id, from: projectID)
                guard upscalingRunTokens[itemID] == runToken else { return }
                upscalingItemIDs.remove(itemID)
                upscalingTasks.removeValue(forKey: itemID)
                upscalingJobContexts.removeValue(forKey: itemID)
                upscalingRunTokens.removeValue(forKey: itemID)
                guard !(error is CancellationError) else { return }
                showError("高解像度化に失敗しました")
                logs.append("高解像度化失敗: \(error.localizedDescription)")
            }
        }
        upscalingTasks[item.id] = task
    }

    /// プレビュー表示中にモデルを切り替えて同一アイテムを再アップスケールする
    func rerunUpscale(payload: UpscalePreviewPayload, model: UpscaleModel) {
        guard model != payload.model, !upscaleRerunning else { return }
        Self.savePreferredUpscaleModel(model)

        let item = payload.originalItem
        let fileURL = projectStore.resolvedFileURL(for: item)
        upscaleRerunning = true

        upscaleRerunTask = Task { @MainActor in
            do {
                let upscaledData = try await Self.runLocalUpscale(fileURL: fileURL, model: model)
                upscaleRerunning = false
                // シートが閉じられていたら結果を反映しない
                guard upscalePreview?.id == payload.id else { return }
                upscalePreview = UpscalePreviewPayload(
                    originalItem: item,
                    originalImageData: payload.originalImageData,
                    upscaledImageData: upscaledData,
                    model: model,
                    jobLogs: payload.jobLogs
                )
            } catch {
                upscaleRerunning = false
                guard !(error is CancellationError) else { return }
                showError("高解像度化に失敗しました")
                logs.append("高解像度化再実行失敗: \(error.localizedDescription)")
            }
        }
    }

    func cancelUpscale(itemID: UUID) {
        upscalingTasks[itemID]?.cancel()
        upscalingTasks.removeValue(forKey: itemID)
        upscalingRunTokens.removeValue(forKey: itemID)
        upscalingItemIDs.remove(itemID)
        if let ctx = upscalingJobContexts.removeValue(forKey: itemID) {
            removeJob(id: ctx.jobID, from: ctx.projectID)
        }
    }

    func commitUpscale(payload: UpscalePreviewPayload, mode: UpscaleApplyMode) {
        upscaleRerunTask?.cancel()
        upscaleRerunTask = nil
        upscaleRerunning = false
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
                touchProject(id: projectID)
                saveState()
                logs.append("高解像度化: 新規アイテム追加 \(newItem.id)")
            } catch {
                showError("高解像度化結果の保存に失敗しました")
                logs.append("高解像度化保存失敗: \(error.localizedDescription)")
            }

        case .overwrite:
            let origURL = projectStore.resolvedFileURL(for: item)
            do {
                try projectStore.writeItemData(data, for: item)
                thumbnailStore.deleteThumbnail(for: item)
                thumbnailStore.writeThumbnail(from: data, item: item)
                originalImageStore.evict(url: origURL)
                thumbnailStore.invalidate(for: item)
                touchProject(id: projectID)
                saveState()
                logs.append("高解像度化: 上書き完了 \(item.id)")
            } catch {
                showError("高解像度化結果の上書きに失敗しました")
                logs.append("高解像度化上書き失敗: \(error.localizedDescription)")
            }
        }
    }

    // Task.detached は親のキャンセルを継承しないため明示的に伝播する
    private static func runLocalUpscale(fileURL: URL, model: UpscaleModel) async throws -> Data {
        let task = Task.detached(priority: .userInitiated) {
            try await ImageUpscaler.upscale(fileURL: fileURL, model: model)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
