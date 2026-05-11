import AppKit
import Foundation

extension DraftCanvasViewModel {
    func switchToProjectIfNeeded(for item: ProjectItem) {
        guard selectedSmartProjectID != nil else { return }
        selectedSmartProjectID = nil
        selectedProjectID = item.projectID
    }

    func edit(item: ProjectItem) {
        switchToProjectIfNeeded(for: item)
        let id = selectedProjectID ?? item.projectID
        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        var inputs = inputsByProject[id] ?? ProjectInputs()
        if let attached = inputs.attachedImage {
            projectStore.cleanupAttachment(id: attached.id)
        }
        inputs.attachedImage = nil
        inputs.prompt = item.prompt
        inputs.aspectRatio = item.aspectRatio
        inputs.editSource = GenerationEditSource(
            projectItemID: item.id,
            filePath: fileURL.path,
            originalPrompt: item.prompt
        )
        inputsByProject[id] = inputs
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].updatedAt = Date()
        }
        logs.append("アイテムを再編集対象にしました: \(fileURL.path)")
    }

    func inpaint(item: ProjectItem) {
        switchToProjectIfNeeded(for: item)
        inpaintMode = .edit
        inpaintingTarget = item
    }

    func maskRemove(item: ProjectItem) {
        switchToProjectIfNeeded(for: item)
        inpaintMode = .remove
        inpaintingTarget = item
    }

    func applyInpaintingMask(item: ProjectItem, strokes: [MaskStroke]) {
        let id = selectedProjectID ?? item.projectID

        let fileURL = item.fileURL(in: projectStore.rootDirectory)

        Task.detached(priority: .userInitiated) {
            do {
                let originalData = try Data(contentsOf: fileURL)
                let imgSource = CGImageSourceCreateWithData(originalData as CFData, nil)
                let imgProps = imgSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                let pw = imgProps?[kCGImagePropertyPixelWidth] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init)
                    ?? 1024
                let ph = imgProps?[kCGImagePropertyPixelHeight] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init)
                    ?? 1024
                let canvasSize = CGSize(width: pw, height: ph)

                guard let maskData = InpaintingMaskCompositor.renderMask(from: strokes, canvasSize: canvasSize) else {
                    await MainActor.run { self.errorToast = "マスク画像の生成に失敗しました。" }
                    return
                }

                let compositeData = try InpaintingMaskCompositor.composite(
                    originalImageData: originalData,
                    maskData: maskData
                )

                let store = await MainActor.run { self.projectStore }
                let maskURL = try store.writeMaskData(maskData, id: item.id)
                let compositeURL = try store.writeCompositeData(compositeData, id: item.id)

                await MainActor.run {
                    var inputs = self.inputsByProject[id] ?? ProjectInputs()
                    if let attached = inputs.attachedImage {
                        self.projectStore.cleanupAttachment(id: attached.id)
                    }
                    inputs.attachedImage = nil
                    inputs.prompt = item.prompt
                    inputs.aspectRatio = item.aspectRatio
                    inputs.editSource = GenerationEditSource(
                        projectItemID: item.id,
                        filePath: fileURL.path,
                        originalPrompt: item.prompt,
                        maskFilePath: maskURL.path,
                        compositeFilePath: compositeURL.path
                    )
                    self.inputsByProject[id] = inputs
                    self.inpaintingTarget = nil
                    self.logs.append("マスク編集を設定しました: \(item.id)")
                }
            } catch {
                await MainActor.run {
                    self.errorToast = "マスクの処理に失敗しました: \(error.localizedDescription)"
                    self.logs.append("マスク編集処理エラー: \(error.localizedDescription)")
                }
            }
        }
    }

    func applyMaskRemoval(item: ProjectItem, strokes: [MaskStroke]) {
        let projectID = selectedProjectID ?? item.projectID
        let fileURL = item.fileURL(in: projectStore.rootDirectory)

        inpaintingTarget = nil

        let fastModel = Self.selectFastLowCostModel(from: availableModels)
        let removalCoordinator = coordinator
        let removalStore = projectStore
        let itemPrompt = item.prompt
        let itemAspectRatio = item.aspectRatio
        let itemID = item.id

        generatingProjectIDs.insert(projectID)
        logs.append("マスク除去を開始しました: \(item.id)")

        Task.detached(priority: .userInitiated) {
            do {
                let originalData = try Data(contentsOf: fileURL)
                let imgSource = CGImageSourceCreateWithData(originalData as CFData, nil)
                let imgProps = imgSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                let pw = imgProps?[kCGImagePropertyPixelWidth] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init)
                    ?? 1024
                let ph = imgProps?[kCGImagePropertyPixelHeight] as? CGFloat
                    ?? (imgProps?[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init)
                    ?? 1024
                let canvasSize = CGSize(width: pw, height: ph)

                guard let maskData = InpaintingMaskCompositor.renderMask(from: strokes, canvasSize: canvasSize) else {
                    await MainActor.run {
                        self.errorToast = "マスク画像の生成に失敗しました。"
                        self.generatingProjectIDs.remove(projectID)
                    }
                    return
                }

                let compositeData = try InpaintingMaskCompositor.composite(
                    originalImageData: originalData,
                    maskData: maskData
                )

                let maskURL = try removalStore.writeMaskData(maskData, id: itemID)
                let compositeURL = try removalStore.writeCompositeData(compositeData, id: itemID)

                let editSource = GenerationEditSource(
                    projectItemID: itemID,
                    filePath: fileURL.path,
                    originalPrompt: itemPrompt,
                    maskFilePath: maskURL.path,
                    compositeFilePath: compositeURL.path,
                    inpaintPurpose: .remove
                )
                let request = GenerationRequest(
                    prompt: itemPrompt,
                    count: 1,
                    concurrency: 1,
                    aspectRatio: itemAspectRatio,
                    editSource: editSource,
                    model: fastModel.id,
                    reasoningEffort: "low"
                )

                let results = await removalCoordinator.run(request: request) { [weak self] job in
                    await MainActor.run { self?.upsert(job, into: projectID) }
                }

                await MainActor.run {
                    self.persistSucceededJobs(results, request: request, projectID: projectID)
                    removalStore.cleanupMaskFiles(id: itemID)
                    self.generatingProjectIDs.remove(projectID)
                    if self.generatingProjectIDs.isEmpty {
                        self.onAllJobsCompleted(results: results)
                    }
                    self.logs.append("マスク除去が完了しました。")
                    self.refreshAccountUsage()
                }
            } catch {
                await MainActor.run {
                    self.errorToast = "マスク除去に失敗しました: \(error.localizedDescription)"
                    self.logs.append("マスク除去エラー: \(error.localizedDescription)")
                    self.generatingProjectIDs.remove(projectID)
                }
            }
        }
    }

    func removeBackground(item: ProjectItem) {
        switchToProjectIfNeeded(for: item)
        let projectID = selectedProjectID ?? item.projectID

        let job = GenerationJob(
            index: jobsByProject[projectID]?.count ?? 0,
            prompt: "背景除去: \(item.prompt.prefix(30))",
            aspectRatio: item.aspectRatio
        )
        upsert(job, into: projectID)

        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        let itemAspectRatio = item.aspectRatio
        let itemPrompt = item.prompt

        Task {
            var running = job
            running.status = .running
            await MainActor.run { [weak self] in self?.upsert(running, into: projectID) }

            do {
                let inputData = try Data(contentsOf: fileURL)
                let outputData = try await BackgroundRemover.process(data: inputData)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var completed = running
                    completed.status = .succeeded
                    completed.imageData = outputData
                    self.upsert(completed, into: projectID)

                    let newItem = ProjectItem(projectID: projectID, prompt: itemPrompt, aspectRatio: itemAspectRatio, isBackgroundRemoved: true)
                    do {
                        try self.projectStore.writeItemData(outputData, for: newItem)
                        self.items.append(newItem)
                        if let img = NSImage(data: outputData) {
                            self.imageCache.setObject(img, forKey: self.fileURL(for: newItem) as NSURL)
                        }
                        if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                            self.projects[idx].updatedAt = Date()
                        }
                        self.saveState()
                        self.logs.append("背景除去完了: \(newItem.id)")
                    } catch {
                        self.errorToast = "背景除去結果の保存に失敗しました"
                        self.logs.append("背景除去結果の保存に失敗: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var failed = running
                    failed.status = .failed
                    failed.errorMessage = error.localizedDescription
                    self.upsert(failed, into: projectID)
                    let message = (error as? BackgroundRemovalError)?.localizedDescription
                        ?? "背景除去に失敗しました"
                    self.errorToast = message
                    self.logs.append("背景除去失敗: \(error.localizedDescription)")
                }
            }
        }
    }
}
