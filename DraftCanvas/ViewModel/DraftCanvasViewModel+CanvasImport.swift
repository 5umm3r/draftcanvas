import AppKit
import Foundation

private actor ImportProgressCounter {
    private(set) var done: Int = 0
    func increment() { done += 1 }
}

extension DraftCanvasViewModel {
    func importImageToCanvas() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.prompt = L("インポート")
        panel.message = L("キャンバスにインポートする画像を選択してください。")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let projectID = selectedProjectID ?? createProject().id
        importImagesAsProjectItems(urls: panel.urls, projectID: projectID)
    }

    // 1枚版（D&D互換ラッパ）
    func importImageAsProjectItem(url: URL, projectID: UUID) {
        importImagesAsProjectItems(urls: [url], projectID: projectID)
    }

    // N枚バッチインポート: 原本コピー優先 + 並列デコード(max4) + 100msスロットリング進捗 + signpost
    func importImagesAsProjectItems(urls: [URL], projectID: UUID) {
        guard selectedFilteringProjectID == nil else {
            appendLog(L("[Import] フィルタリングプロジェクト選択中はスキップ"))
            return
        }
        guard !urls.isEmpty else { return }

        let total = urls.count
        importProgress = (done: 0, total: total)
        importError = nil
        #if DEBUG
        appendLog(CanvasMetrics.logSummary(tag: "import-start"))
        #endif

        let projectStoreRef = projectStore
        let thumbnailStoreRef = thumbnailStore
        let counter = ImportProgressCounter()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let batchID = ImportSignposter.signposter.makeSignpostID()
            let batchState = ImportSignposter.signposter.beginInterval("import-batch", id: batchID, "\(total) images")

            struct ImportResult {
                let index: Int
                let item: ProjectItem
            }

            var results: [ImportResult] = []
            var rollbackItems: [ProjectItem] = []
            var errorMessage: String? = nil

            // 100ms flush Task: 進捗をスロットリングして MainActor 更新
            let flushTask = Task.detached { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    let current = await counter.done
                    await MainActor.run { [weak self] in
                        self?.importProgress?.done = current
                    }
                    ImportSignposter.signposter.emitEvent("progress-flush", "\(current)/\(total)")
                    if current >= total { break }
                }
            }

            await withTaskGroup(of: Result<ImportResult, Error>.self) { group in
                let maxConcurrent = 4
                var iterator = urls.enumerated().makeIterator()

                func addJob(index: Int, url: URL) {
                    group.addTask {
                        let decodeID = ImportSignposter.signposter.makeSignpostID()
                        let decodeState = ImportSignposter.signposter.beginInterval("decode", id: decodeID, "\(url.lastPathComponent)")
                        do {
                            let decoded = try self.decodeImportImage(from: url)
                            ImportSignposter.signposter.endInterval("decode", decodeState)

                            let name = url.deletingPathExtension().lastPathComponent
                            let item = ProjectItem(
                                projectID: projectID,
                                prompt: name,
                                aspectRatio: decoded.aspectRatio,
                                actualAspectRatio: decoded.actualAspectRatio,
                                isImported: true
                            )

                            let writeID = ImportSignposter.signposter.makeSignpostID()
                            let writeState = ImportSignposter.signposter.beginInterval("write-item", id: writeID)
                            try projectStoreRef.writeItemData(decoded.data, for: item, fileExtension: decoded.fileExtension)
                            ImportSignposter.signposter.endInterval("write-item", writeState)

                            let thumbID = ImportSignposter.signposter.makeSignpostID()
                            let thumbState = ImportSignposter.signposter.beginInterval("thumb", id: thumbID)
                            thumbnailStoreRef.writeThumbnail(from: decoded.data, item: item)
                            ImportSignposter.signposter.endInterval("thumb", thumbState)

                            await counter.increment()
                            return .success(ImportResult(index: index, item: item))
                        } catch {
                            ImportSignposter.signposter.endInterval("decode", decodeState)
                            return .failure(error)
                        }
                    }
                }

                for _ in 0..<maxConcurrent {
                    guard let (index, url) = iterator.next() else { break }
                    addJob(index: index, url: url)
                }

                for await result in group {
                    switch result {
                    case .success(let r):
                        results.append(r)
                        rollbackItems.append(r.item)
                        if errorMessage == nil, let (index, url) = iterator.next() {
                            addJob(index: index, url: url)
                        }
                    case .failure(let error):
                        if errorMessage == nil {
                            errorMessage = L("インポート失敗: \(error.localizedDescription)")
                            group.cancelAll()
                        }
                    }
                }
            }

            flushTask.cancel()

            if let errorMessage {
                for item in rollbackItems {
                    projectStoreRef.deleteItemFile(item)
                    thumbnailStoreRef.deleteThumbnail(for: item)
                }
                ImportSignposter.signposter.endInterval("import-batch", batchState, "error")
                await MainActor.run { [weak self] in
                    self?.importError = errorMessage
                    self?.importProgress = nil
                    self?.appendLog("[Import] エラー全体中断、\(rollbackItems.count)件ロールバック: \(errorMessage)")
                }
                return
            }

            let sortedItems = results.sorted { $0.index < $1.index }.map(\.item)
            let projectIDToUpdate = projectID

            let finalizeID = ImportSignposter.signposter.makeSignpostID()
            let finalizeState = ImportSignposter.signposter.beginInterval("main-finalize", id: finalizeID)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoadingProjects = true
                self.items.append(contentsOf: sortedItems)
                self.isLoadingProjects = false
                self.recomputeDisplayedItems()
                if let idx = self.projects.firstIndex(where: { $0.id == projectIDToUpdate }) {
                    self.projects[idx].updatedAt = Date()
                }
                self.saveStateAsync()
                self.importProgress = nil
                self.appendLog("[Import] \(sortedItems.count)枚インポート完了")
                #if DEBUG
                self.appendLog(CanvasMetrics.logSummary(tag: "import-done"))
                #endif
            }
            ImportSignposter.signposter.endInterval("main-finalize", finalizeState)
            ImportSignposter.signposter.endInterval("import-batch", batchState, "done \(sortedItems.count)")
        }
    }

    func importImageAsProjectItem(image: NSImage, projectID: UUID) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let pngData = rep.representation(using: .png, properties: [:]) else {
                await MainActor.run { self.errorToast = L("画像の変換に失敗しました") }
                return
            }
            let aspectRatio = self.aspectRatioFromImageData(pngData)
            let actualRatio = self.pixelAspectRatioFromImageData(pngData)
            let newItem = ProjectItem(
                projectID: projectID,
                prompt: "Imported Image",
                aspectRatio: aspectRatio,
                actualAspectRatio: actualRatio,
                isImported: true
            )
            do {
                try self.projectStore.writeItemData(pngData, for: newItem)
                let thumbnailStoreRef = self.thumbnailStore
                thumbnailStoreRef.writeThumbnail(from: pngData, item: newItem)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.items.append(newItem)
                    if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                        self.projects[idx].updatedAt = Date()
                    }
                    self.saveState()
                    self.logs.append("画像をインポートしました (ドラッグ&ドロップ)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorToast = L("画像のインポートに失敗しました")
                    self?.logs.append("インポートエラー: \(error.localizedDescription)")
                }
            }
        }
    }
}
