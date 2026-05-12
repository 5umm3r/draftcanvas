import AppKit
import Foundation

extension DraftCanvasViewModel {
    func importImageToCanvas() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.prompt = "インポート"
        panel.message = "キャンバスにインポートする画像を選択してください。"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let projectID = selectedProjectID ?? createProject().id
        importImagesAsProjectItems(urls: panel.urls, projectID: projectID)
    }

    // 1枚版（D&D互換ラッパ）
    func importImageAsProjectItem(url: URL, projectID: UUID) {
        importImagesAsProjectItems(urls: [url], projectID: projectID)
    }

    // N枚バッチインポート: 並列デコード+書き込み(max4並列) → 選択順append → 末尾1回保存
    func importImagesAsProjectItems(urls: [URL], projectID: UUID) {
        guard selectedSmartProjectID == nil else {
            appendLog("[Import] Smart プロジェクト選択中はスキップ")
            return
        }
        guard !urls.isEmpty else { return }

        importProgress = (done: 0, total: urls.count)
        importError = nil
        #if DEBUG
        appendLog(CanvasMetrics.logSummary(tag: "import-start"))
        #endif

        let projectStoreRef = projectStore
        let thumbnailStoreRef = thumbnailStore

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            struct ImportResult {
                let index: Int
                let item: ProjectItem
            }

            var results: [ImportResult] = []
            var rollbackItems: [ProjectItem] = []
            var errorMessage: String? = nil

            await withTaskGroup(of: Result<ImportResult, Error>.self) { group in
                let maxConcurrent = 4
                var iterator = urls.enumerated().makeIterator()

                func addJob(index: Int, url: URL) {
                    group.addTask {
                        do {
                            let pngData = try self.loadAndNormalizeImage(from: url)
                            let aspectRatio = self.aspectRatioFromImageData(pngData)
                            let name = url.deletingPathExtension().lastPathComponent
                            let item = ProjectItem(
                                projectID: projectID,
                                prompt: name,
                                aspectRatio: aspectRatio,
                                isImported: true
                            )
                            try projectStoreRef.writeItemData(pngData, for: item)
                            thumbnailStoreRef.writeThumbnail(from: pngData, item: item)
                            return .success(ImportResult(index: index, item: item))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // 初期ジョブ投入
                for _ in 0..<maxConcurrent {
                    guard let (index, url) = iterator.next() else { break }
                    addJob(index: index, url: url)
                }

                for await result in group {
                    switch result {
                    case .success(let r):
                        results.append(r)
                        rollbackItems.append(r.item)
                        await MainActor.run { [weak self] in
                            self?.importProgress?.done += 1
                        }
                        // 次ジョブ投入
                        if errorMessage == nil, let (index, url) = iterator.next() {
                            addJob(index: index, url: url)
                        }
                    case .failure(let error):
                        if errorMessage == nil {
                            errorMessage = "インポート失敗: \(error.localizedDescription)"
                            group.cancelAll()
                        }
                    }
                }
            }

            if let errorMessage {
                for item in rollbackItems {
                    projectStoreRef.deleteItemFile(item)
                    thumbnailStoreRef.deleteThumbnail(for: item)
                }
                await MainActor.run { [weak self] in
                    self?.importError = errorMessage
                    self?.importProgress = nil
                    self?.appendLog("[Import] エラー全体中断、\(rollbackItems.count)件ロールバック: \(errorMessage)")
                }
                return
            }

            let sortedItems = results.sorted { $0.index < $1.index }.map(\.item)
            let projectIDToUpdate = projectID

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
        }
    }

    func importImageAsProjectItem(image: NSImage, projectID: UUID) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            errorToast = "画像の変換に失敗しました"
            return
        }
        let aspectRatio = aspectRatioFromImageData(pngData)
        let newItem = ProjectItem(
            projectID: projectID,
            prompt: "Imported Image",
            aspectRatio: aspectRatio,
            isImported: true
        )
        do {
            try projectStore.writeItemData(pngData, for: newItem)
            items.append(newItem)
            thumbnailStore.writeThumbnail(from: pngData, item: newItem)
            if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
            logs.append("画像をインポートしました (ドラッグ&ドロップ)")
        } catch {
            errorToast = "画像のインポートに失敗しました"
            logs.append("インポートエラー: \(error.localizedDescription)")
        }
    }
}
