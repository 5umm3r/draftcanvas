import AppKit
import Foundation

extension DraftCanvasViewModel {
    func edit(item: ProjectItem) {
        activeEditProjectID = item.projectID
        let id = item.projectID
        let fileURL = projectStore.resolvedFileURL(for: item)
        var inputs = inputsByProject[id] ?? ProjectInputs()
        if let attached = inputs.attachedImage {
            projectStore.cleanupAttachment(id: attached.id)
        }

        // 背景除去済みアイテムは元画像をサムネイル添付として復元する
        if item.isBackgroundRemoved, let originalID = item.editedFromItemID,
           let original = items.first(where: { $0.id == originalID }) {
            let originalURL = projectStore.resolvedFileURL(for: original)
            // AttachedImage.id に originalID を使うと cleanupAttachment は
            // attachments/ を探すため items/ の元ファイルは削除されない
            inputs.attachedImage = AttachedImage(
                id: originalID,
                filePath: originalURL.path,
                originalFileName: nil
            )
        } else {
            inputs.attachedImage = AttachedImage(
                id: item.id,
                filePath: fileURL.path,
                originalFileName: nil
            )
        }

        inputs.prompt = ""
        inputs.aspectRatio = item.aspectRatio
        inputs.editSource = GenerationEditSource(
            projectItemID: item.id,
            filePath: fileURL.path,
            originalPrompt: item.prompt
        )
        inputsByProject[id] = inputs
        focusPromptTrigger = UUID()
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].updatedAt = Date()
        }
        logs.append("アイテムを再編集対象にしました: \(fileURL.path)")
    }

    func openMaskEditor(item: ProjectItem) {
        inpaintingTarget = item
    }

    func applyInpaintingMask(item: ProjectItem, strokes: [MaskStroke]) {
        let id = selectedProjectID ?? item.projectID

        let fileURL = projectStore.resolvedFileURL(for: item)

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
                    await MainActor.run { self.errorToast = String(localized: "マスク画像の生成に失敗しました。") }
                    return
                }

                let compositeData = try InpaintingMaskCompositor.composite(
                    originalImageData: originalData,
                    maskData: maskData
                )

                let store = await MainActor.run { self.projectStore }
                let maskURL = try store.writeMaskData(maskData, id: item.id)
                let compositeURL = try store.writeCompositeData(compositeData, id: item.id)
                try? store.writeStrokesData(strokes, id: item.id)
                if let previewData = try? InpaintingMaskCompositor.renderPreview(
                    originalImageData: originalData, maskData: maskData
                ) {
                    try? store.writePreviewData(previewData, id: item.id)
                }

                await MainActor.run {
                    var inputs = self.inputsByProject[id] ?? ProjectInputs()
                    if let attached = inputs.attachedImage {
                        self.projectStore.cleanupAttachment(id: attached.id)
                    }
                    inputs.attachedImage = AttachedImage(
                        id: item.id,
                        filePath: fileURL.path,
                        originalFileName: nil
                    )
                    inputs.prompt = ""
                    inputs.aspectRatio = item.aspectRatio
                    inputs.editSource = GenerationEditSource(
                        projectItemID: item.id,
                        filePath: fileURL.path,
                        originalPrompt: item.prompt,
                        maskFilePath: maskURL.path,
                        compositeFilePath: compositeURL.path
                    )
                    self.inputsByProject[id] = inputs
                    self.activeEditProjectID = id
                    self.inpaintingTarget = nil
                    self.focusPromptTrigger = UUID()
                    self.logs.append("マスク編集を設定しました: \(item.id)")
                }
            } catch {
                await MainActor.run {
                    self.errorToast = String(localized: "マスクの処理に失敗しました: \(error.localizedDescription)")
                    self.logs.append("マスク編集処理エラー: \(error.localizedDescription)")
                }
            }
        }
    }

    func applyMaskRemoval(item: ProjectItem, strokes: [MaskStroke]) {
        let projectID = selectedProjectID ?? item.projectID
        let fileURL = projectStore.resolvedFileURL(for: item)

        inpaintingTarget = nil
        activeEditProjectID = projectID

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
                        self.errorToast = String(localized: "マスク画像の生成に失敗しました。")
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
                    self.errorToast = String(localized: "マスク除去に失敗しました: \(error.localizedDescription)")
                    self.logs.append("マスク除去エラー: \(error.localizedDescription)")
                    self.generatingProjectIDs.remove(projectID)
                }
            }
        }
    }

    func startBackgroundRemoval(item: ProjectItem) {
        let projectID = selectedProjectID ?? item.projectID

        let job = GenerationJob(
            index: jobsByProject[projectID]?.count ?? 0,
            prompt: "背景除去: \(item.prompt.prefix(30))",
            aspectRatio: item.aspectRatio
        )
        upsert(job, into: projectID)

        let fileURL = projectStore.resolvedFileURL(for: item)

        Task {
            var running = job
            running.status = .running
            upsert(running, into: projectID)

            do {
                let inputData = try Data(contentsOf: fileURL)
                let session = try await BackgroundRemover.extractMask(from: inputData)
                let initialData = try BackgroundRemover.apply(session: session, edgeStrength: 0.5, mode: session.initialMode)

                var succeeded = running
                succeeded.status = .succeeded
                upsert(succeeded, into: projectID)

                backgroundRemovalPreview = BackgroundRemovalPreview(
                    item: item,
                    session: session,
                    initialData: initialData
                )
                logs.append("背景除去プレビュー準備完了: \(item.id)")
            } catch {
                var failed = running
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                upsert(failed, into: projectID)
                let message = (error as? BackgroundRemovalError)?.localizedDescription
                    ?? String(localized: "背景除去に失敗しました")
                errorToast = message
                logs.append("背景除去失敗: \(error.localizedDescription)")
            }
        }
    }

    func commitBackgroundRemoval(item: ProjectItem, data: Data) {
        let projectID = selectedProjectID ?? item.projectID

        backgroundRemovalPreview = nil

        do {
            let newItem = ProjectItem(
                projectID: projectID,
                prompt: item.prompt,
                aspectRatio: item.aspectRatio,
                actualAspectRatio: item.actualAspectRatio,
                editedFromItemID: item.id,
                isBackgroundRemoved: true
            )
            try projectStore.writeItemData(data, for: newItem)
            items.append(newItem)
            thumbnailStore.writeThumbnail(from: data, item: newItem)
            if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
            logs.append("背景除去保存完了: \(newItem.id)")
        } catch {
            errorToast = String(localized: "背景除去結果の保存に失敗しました")
            logs.append("背景除去保存失敗: \(error.localizedDescription)")
        }
    }
}
