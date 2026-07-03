import AppKit
import Foundation

extension DraftCanvasViewModel {
    func openOutpaintEditor(for item: ProjectItem, initialInsets: OutpaintInsets = .zero) {
        outpaintTarget = OutpaintTarget(item: item, initialInsets: initialInsets)
    }

    // inpaint edit モードと同様: editSource を設定してメイン画面に戻り、ユーザーがプロンプト入力後に生成
    func prepareOutpaint(item: ProjectItem, insets: OutpaintInsets) {
        guard !insets.isEmpty else { return }

        let projectID = selectedProjectID ?? item.projectID
        let fileURL = projectStore.resolvedFileURL(for: item)

        outpaintTarget = nil
        outpaintInsetsCache[item.id] = insets

        Task.detached(priority: .userInitiated) {
            do {
                let monitor = await MainActor.run { self.syncMonitor }
                let originalData = try await self.imageLoader.loadData(at: fileURL, syncMonitor: monitor)
                await self.cacheEviction.recordAccess(url: fileURL)
                let compositorResult = try OutpaintCompositor.composite(
                    originalImageData: originalData,
                    insets: insets
                )

                let store = await MainActor.run { self.projectStore }
                let maskURL = try store.writeMaskData(compositorResult.maskData, id: item.id)
                let compositeURL = try store.writeCompositeData(compositorResult.compositeData, id: item.id)

                await MainActor.run {
                    var inputs = self.inputsByProject[projectID] ?? ProjectInputs()
                    if let attached = inputs.attachedImage {
                        self.projectStore.cleanupAttachment(id: attached.id)
                    }
                    inputs.attachedImage = AttachedImage(
                        id: item.id,
                        filePath: fileURL.path,
                        originalFileName: nil
                    )
                    inputs.prompt = ""
                    inputs.aspectRatio = .auto
                    inputs.editSource = GenerationEditSource(
                        projectItemID: item.id,
                        filePath: fileURL.path,
                        originalPrompt: item.prompt,
                        maskFilePath: maskURL.path,
                        compositeFilePath: compositeURL.path,
                        inpaintPurpose: .outpaint
                    )
                    self.inputsByProject[projectID] = inputs
                    self.activeEditProjectID = projectID
                    self.focusPromptTrigger = UUID()
                    self.logs.append("アウトペイント準備完了: \(item.id)")
                }
            } catch {
                await MainActor.run {
                    self.showError("アウトペイントの準備に失敗しました: \(error.localizedDescription)")
                    self.logs.append("アウトペイント準備エラー: \(error.localizedDescription)")
                }
            }
        }
    }

    // 即時生成モード: 自動背景継続
    func applyOutpaint(item: ProjectItem, insets: OutpaintInsets) {
        guard !insets.isEmpty else { return }
        guard let fastModel = Self.selectFastLowCostModel(from: availableModels) else {
            showError("利用可能なモデルがありません")
            return
        }

        let projectID = selectedProjectID ?? item.projectID
        let fileURL = projectStore.resolvedFileURL(for: item)

        outpaintTarget = nil
        activeEditProjectID = projectID

        let itemPrompt = item.prompt
        let itemID = item.id
        let translateToEnglishRef = translateToEnglish

        generatingProjectIDs.insert(projectID)
        activityTracker.begin()
        logs.append("アウトペイントを開始しました: \(item.id)")

        let runID = UUID()
        if generationTasks[projectID] == nil { generationTasks[projectID] = [:] }

        let outpaintTask = Task.detached(priority: .userInitiated) {
            do {
                let monitor = await MainActor.run { self.syncMonitor }
                let originalData = try await self.imageLoader.loadData(at: fileURL, syncMonitor: monitor)
                await self.cacheEviction.recordAccess(url: fileURL)

                let compositorResult = try OutpaintCompositor.composite(
                    originalImageData: originalData,
                    insets: insets
                )

                let store = await MainActor.run { self.projectStore }
                let maskURL = try store.writeMaskData(compositorResult.maskData, id: itemID)
                let compositeURL = try store.writeCompositeData(compositorResult.compositeData, id: itemID)

                let editSource = GenerationEditSource(
                    projectItemID: itemID,
                    filePath: fileURL.path,
                    originalPrompt: itemPrompt,
                    maskFilePath: maskURL.path,
                    compositeFilePath: compositeURL.path,
                    inpaintPurpose: .outpaint
                )

                let request = GenerationRequest(
                    prompt: itemPrompt,
                    count: 1,
                    concurrency: 1,
                    aspectRatio: .auto,
                    editSource: editSource,
                    model: fastModel.id,
                    reasoningEffort: "low",
                    translateToEnglish: translateToEnglishRef
                )

                let preparedRequest = await self.prepareRequestForGeneration(request)
                try Task.checkCancellation()
                let outpaintCoordinator = await MainActor.run { self.coordinator }

                let results = await outpaintCoordinator.run(request: preparedRequest) { [weak self] job in
                    await MainActor.run { self?.handleJobUpdate(job, into: projectID, request: preparedRequest) }
                }

                await MainActor.run {
                    store.cleanupMaskFiles(id: itemID)
                    // キャンセル済み（cancelProjectRuns が登録除去・フラグ処理済み）なら
                    // 後続の実行の生成中状態を壊さないよう何もしない
                    guard self.generationTasks[projectID]?[runID] != nil else { return }
                    self.generatingProjectIDs.remove(projectID)
                    self.activityTracker.end()
                    self.generationTasks[projectID]?.removeValue(forKey: runID)
                    if self.generatingProjectIDs.isEmpty {
                        self.onAllJobsCompleted(results: results)
                    }
                    self.logs.append("アウトペイントが完了しました。")
                    self.refreshAccountUsage()
                }
            } catch {
                await MainActor.run {
                    let projectStoreRef = self.projectStore
                    projectStoreRef.cleanupMaskFiles(id: itemID)
                    guard self.generationTasks[projectID]?[runID] != nil else { return }
                    self.generatingProjectIDs.remove(projectID)
                    self.activityTracker.end()
                    self.generationTasks[projectID]?.removeValue(forKey: runID)
                    guard !(error is CancellationError) else { return }
                    self.showError("アウトペイントに失敗しました: \(error.localizedDescription)")
                    self.logs.append("アウトペイントエラー: \(error.localizedDescription)")
                }
            }
        }
        generationTasks[projectID]?[runID] = outpaintTask
    }
}
