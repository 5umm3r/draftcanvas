import AppKit
import Foundation

extension DraftCanvasViewModel {
    func deleteItem(_ item: ProjectItem) {
        projectStore.deleteItemFile(item)
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id { selectedItemID = nil }
        if let idx = projects.firstIndex(where: { $0.id == item.projectID }) {
            projects[idx].updatedAt = Date()
        }
        saveState()
    }

    func duplicateItem(_ item: ProjectItem) {
        let newItem = ProjectItem(
            id: UUID(),
            projectID: item.projectID,
            prompt: item.prompt,
            revisedPrompt: item.revisedPrompt,
            aspectRatio: item.aspectRatio,
            createdAt: item.createdAt,
            errorMessage: item.errorMessage,
            editedFromItemID: nil,
            hasSVG: item.hasSVG,
            isBackgroundRemoved: item.isBackgroundRemoved,
            isImported: item.isImported
        )
        do {
            try FileManager.default.createDirectory(at: projectStore.itemsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: item.fileURL(in: projectStore.rootDirectory),
                to: newItem.fileURL(in: projectStore.rootDirectory)
            )
            if item.hasSVG {
                try FileManager.default.copyItem(
                    at: item.svgFileURL(in: projectStore.rootDirectory),
                    to: newItem.svgFileURL(in: projectStore.rootDirectory)
                )
            }
            if let img = cachedImage(for: item) {
                imageCache.setObject(img, forKey: newItem.fileURL(in: projectStore.rootDirectory) as NSURL)
            }
            items.append(newItem)
            if let idx = projects.firstIndex(where: { $0.id == item.projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
        } catch {
            errorToast = "アイテムの複製に失敗しました"
            logs.append("複製エラー: \(error.localizedDescription)")
        }
    }

    func copyItemToProject(_ item: ProjectItem, targetProjectID: UUID) {
        let newItem = ProjectItem(
            id: UUID(),
            projectID: targetProjectID,
            prompt: item.prompt,
            revisedPrompt: item.revisedPrompt,
            aspectRatio: item.aspectRatio,
            createdAt: item.createdAt,
            errorMessage: item.errorMessage,
            editedFromItemID: nil,
            hasSVG: item.hasSVG,
            isBackgroundRemoved: item.isBackgroundRemoved,
            isImported: item.isImported
        )
        do {
            try FileManager.default.createDirectory(at: projectStore.itemsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: item.fileURL(in: projectStore.rootDirectory),
                to: newItem.fileURL(in: projectStore.rootDirectory)
            )
            if item.hasSVG {
                try FileManager.default.copyItem(
                    at: item.svgFileURL(in: projectStore.rootDirectory),
                    to: newItem.svgFileURL(in: projectStore.rootDirectory)
                )
            }
            if let img = cachedImage(for: item) {
                imageCache.setObject(img, forKey: newItem.fileURL(in: projectStore.rootDirectory) as NSURL)
            }
            items.append(newItem)
            if let idx = projects.firstIndex(where: { $0.id == targetProjectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
        } catch {
            errorToast = "アイテムのコピーに失敗しました"
            logs.append("コピーエラー: \(error.localizedDescription)")
        }
    }

    func moveItemToProject(_ item: ProjectItem, targetProjectID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let sourceProjectID = items[idx].projectID
        items[idx].projectID = targetProjectID
        items[idx].editedFromItemID = nil
        if selectedItemID == item.id { selectedItemID = nil }
        if let srcIdx = projects.firstIndex(where: { $0.id == sourceProjectID }) {
            projects[srcIdx].updatedAt = Date()
        }
        if let dstIdx = projects.firstIndex(where: { $0.id == targetProjectID }) {
            projects[dstIdx].updatedAt = Date()
        }
        saveState()
    }

    func reveal(item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL(in: projectStore.rootDirectory)])
    }

    func fileURL(for item: ProjectItem) -> URL {
        item.fileURL(in: projectStore.rootDirectory)
    }

    func cachedImage(for item: ProjectItem) -> NSImage? {
        let url = fileURL(for: item) as NSURL
        if let cached = imageCache.object(forKey: url) { return cached }
        guard let img = NSImage(contentsOf: url as URL) else { return nil }
        imageCache.setObject(img, forKey: url)
        return img
    }

    func ordinalForItem(_ item: ProjectItem, in projectID: UUID) -> Int {
        let sorted = items
            .filter { $0.projectID == projectID }
            .sorted { $0.createdAt < $1.createdAt }
        return (sorted.firstIndex(of: item) ?? 0) + 1
    }

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedItemIDs.removeAll()
        }
    }

    func toggleMultiSelection(_ item: ProjectItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        selectedItemID = nil
        selectedJobID = nil
    }

    func clearMultiSelection() {
        selectedItemIDs.removeAll()
    }
}
