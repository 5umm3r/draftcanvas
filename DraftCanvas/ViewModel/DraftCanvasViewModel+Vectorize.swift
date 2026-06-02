import AppKit
import Foundation

extension DraftCanvasViewModel {
    func vectorize(item: ProjectItem) {
        let projectID = selectedProjectID ?? item.projectID

        vectorizingItemIDs.insert(item.id)

        let fileURL = projectStore.resolvedFileURL(for: item)
        let itemAspectRatio = item.aspectRatio
        let itemActualAspectRatio = item.actualAspectRatio
        let itemPrompt = item.prompt
        let itemID = item.id

        let task = Task {
            do {
                try Task.checkCancellation()
                let inputData = try Data(contentsOf: fileURL)
                try Task.checkCancellation()
                let result = try await ImageVectorizer.process(data: inputData)
                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.vectorizingItemIDs.remove(itemID)
                    self.vectorizationTasks.removeValue(forKey: itemID)

                    let newItem = ProjectItem(
                        projectID: projectID,
                        prompt: itemPrompt,
                        aspectRatio: itemAspectRatio,
                        actualAspectRatio: itemActualAspectRatio,
                        hasSVG: true
                    )
                    do {
                        try self.projectStore.writeItemData(result.previewPNGData, for: newItem)
                        try self.projectStore.writeSVGData(result.svgData, for: newItem)
                        self.items.append(newItem)
                        self.thumbnailStore.writeThumbnail(from: result.previewPNGData, item: newItem)
                        self.touchProject(id: projectID)
                        self.saveState()
                        self.logs.append("ベクター化完了: \(newItem.id)")
                    } catch {
                        self.showError("ベクター化結果の保存に失敗しました")
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
                        ?? String(localized: "ベクター化に失敗しました")
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
