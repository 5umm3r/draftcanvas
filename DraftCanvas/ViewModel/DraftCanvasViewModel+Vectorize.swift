import AppKit
import Foundation

extension DraftCanvasViewModel {
    func vectorize(item: ProjectItem) {
        switchToProjectIfNeeded(for: item)
        let projectID = selectedProjectID ?? item.projectID

        vectorizingItemIDs.insert(item.id)

        let fileURL = item.fileURL(in: projectStore.rootDirectory)
        let itemAspectRatio = item.aspectRatio
        let itemPrompt = item.prompt
        let itemID = item.id

        let task = Task {
            do {
                let inputData = try Data(contentsOf: fileURL)
                let result = try await ImageVectorizer.process(data: inputData)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.vectorizingItemIDs.remove(itemID)
                    self.vectorizationTasks.removeValue(forKey: itemID)

                    let newItem = ProjectItem(
                        projectID: projectID,
                        prompt: itemPrompt,
                        aspectRatio: itemAspectRatio,
                        hasSVG: true
                    )
                    do {
                        try self.projectStore.writeItemData(result.previewPNGData, for: newItem)
                        try self.projectStore.writeSVGData(result.svgData, for: newItem)
                        self.items.append(newItem)
                        if let img = NSImage(data: result.previewPNGData) {
                            self.imageCache.setObject(img, forKey: self.fileURL(for: newItem) as NSURL, cost: img.estimatedBytes)
                        }
                        self.thumbnailStore.writeThumbnail(from: result.previewPNGData, item: newItem)
                        if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                            self.projects[idx].updatedAt = Date()
                        }
                        self.saveState()
                        self.logs.append("ベクター化完了: \(newItem.id)")
                    } catch {
                        self.errorToast = "ベクター化結果の保存に失敗しました"
                        self.logs.append("ベクター化結果の保存に失敗: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.vectorizingItemIDs.remove(itemID)
                    self.vectorizationTasks.removeValue(forKey: itemID)
                    guard !(error is CancellationError) else { return }
                    let message = (error as? ImageVectorizationError)?.localizedDescription
                        ?? "ベクター化に失敗しました"
                    self.errorToast = message
                    self.logs.append("ベクター化失敗: \(error.localizedDescription)")
                }
            }
        }
        vectorizationTasks[item.id] = task
    }

    func cancelVectorization(for item: ProjectItem) {
        vectorizationTasks[item.id]?.cancel()
        vectorizationTasks.removeValue(forKey: item.id)
        vectorizingItemIDs.remove(item.id)
    }
}
