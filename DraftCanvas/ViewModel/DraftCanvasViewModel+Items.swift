import AppKit
import Foundation

extension DraftCanvasViewModel {

    // MARK: - Private helpers (no saveState, no selectedItemID side-effects)

    private func performDelete(_ item: ProjectItem) {
        projectStore.deleteItemFile(item)
        thumbnailStore.deleteThumbnail(for: item)
        items.removeAll { $0.id == item.id }
        if let idx = projects.firstIndex(where: { $0.id == item.projectID }) {
            projects[idx].updatedAt = Date()
        }
    }

    private func performMove(_ item: ProjectItem, targetProjectID: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              items[idx].projectID != targetProjectID else { return false }
        let sourceProjectID = items[idx].projectID
        items[idx].projectID = targetProjectID
        items[idx].editedFromItemID = nil
        if let srcIdx = projects.firstIndex(where: { $0.id == sourceProjectID }) {
            projects[srcIdx].updatedAt = Date()
        }
        if let dstIdx = projects.firstIndex(where: { $0.id == targetProjectID }) {
            projects[dstIdx].updatedAt = Date()
        }
        return true
    }

    private func performCopy(_ item: ProjectItem, targetProjectID: UUID) -> Bool {
        let newItem = ProjectItem(
            id: UUID(),
            projectID: targetProjectID,
            prompt: item.prompt,
            revisedPrompt: item.revisedPrompt,
            aspectRatio: item.aspectRatio,
            actualAspectRatio: item.actualAspectRatio,
            createdAt: item.createdAt,
            errorMessage: item.errorMessage,
            editedFromItemID: nil,
            hasSVG: item.hasSVG,
            isBackgroundRemoved: item.isBackgroundRemoved,
            isImported: item.isImported
        )
        do {
            try projectStore.copyItemFile(from: item, to: newItem)
            if item.hasSVG {
                try FileManager.default.copyItem(
                    at: item.svgFileURL(in: projectStore.rootDirectory),
                    to: newItem.svgFileURL(in: projectStore.rootDirectory)
                )
            }
            thumbnailStore.writeThumbnail(from: projectStore.resolvedFileURL(for: newItem), item: newItem)
            items.append(newItem)
            if let idx = projects.firstIndex(where: { $0.id == targetProjectID }) {
                projects[idx].updatedAt = Date()
            }
            return true
        } catch {
            logs.append("コピーエラー: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Single-item public API

    func deleteItem(_ item: ProjectItem) {
        performDelete(item)
        if selectedItemID == item.id { selectedItemID = nil }
        saveState()
    }

    func duplicateItem(_ item: ProjectItem) {
        let newItem = ProjectItem(
            id: UUID(),
            projectID: item.projectID,
            prompt: item.prompt,
            revisedPrompt: item.revisedPrompt,
            aspectRatio: item.aspectRatio,
            actualAspectRatio: item.actualAspectRatio,
            createdAt: item.createdAt,
            errorMessage: item.errorMessage,
            editedFromItemID: nil,
            hasSVG: item.hasSVG,
            isBackgroundRemoved: item.isBackgroundRemoved,
            isImported: item.isImported
        )
        do {
            try projectStore.copyItemFile(from: item, to: newItem)
            if item.hasSVG {
                try FileManager.default.copyItem(
                    at: item.svgFileURL(in: projectStore.rootDirectory),
                    to: newItem.svgFileURL(in: projectStore.rootDirectory)
                )
            }
            thumbnailStore.writeThumbnail(from: projectStore.resolvedFileURL(for: newItem), item: newItem)
            items.append(newItem)
            if let idx = projects.firstIndex(where: { $0.id == item.projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
        } catch {
            errorToast = String(localized: "アイテムの複製に失敗しました")
            logs.append("複製エラー: \(error.localizedDescription)")
        }
    }

    func copyItemToProject(_ item: ProjectItem, targetProjectID: UUID) {
        if !performCopy(item, targetProjectID: targetProjectID) {
            errorToast = String(localized: "アイテムのコピーに失敗しました")
        }
        saveState()
    }

    func moveItemToProject(_ item: ProjectItem, targetProjectID: UUID) {
        guard performMove(item, targetProjectID: targetProjectID) else { return }
        if selectedItemID == item.id { selectedItemID = nil }
        saveState()
    }

    // MARK: - Batch public API (returns failure count)

    @discardableResult
    func deleteItems(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        let targets = items.filter { ids.contains($0.id) }
        for item in targets {
            performDelete(item)
        }
        if let sel = selectedItemID, ids.contains(sel) { selectedItemID = nil }
        selectedItemIDs.subtract(ids)
        saveState()
        return 0
    }

    @discardableResult
    func moveItems(ids: Set<UUID>, targetProjectID: UUID) -> Int {
        guard !ids.isEmpty else { return 0 }
        let targets = items.filter { ids.contains($0.id) }
        var failed = 0
        for item in targets {
            if !performMove(item, targetProjectID: targetProjectID) { failed += 1 }
        }
        if let sel = selectedItemID, ids.contains(sel) { selectedItemID = nil }
        selectedItemIDs.subtract(ids)
        saveState()
        return failed
    }

    @discardableResult
    func copyItems(ids: Set<UUID>, targetProjectID: UUID) -> Int {
        guard !ids.isEmpty else { return 0 }
        let targets = items.filter { ids.contains($0.id) }
        var failed = 0
        for item in targets {
            if !performCopy(item, targetProjectID: targetProjectID) { failed += 1 }
        }
        saveState()
        return failed
    }

    // MARK: - Utilities

    func reveal(item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([projectStore.resolvedFileURL(for: item)])
    }

    @discardableResult
    func copyItemToClipboard(_ item: ProjectItem) -> Bool {
        let url = fileURL(for: item)
        guard
            let imageData = try? Data(contentsOf: url),
            let image = NSImage(data: imageData)
        else { return false }
        ImageClipboard.copy(imageData: imageData, image: image)
        return true
    }

    func fileURL(for item: ProjectItem) -> URL {
        projectStore.resolvedFileURL(for: item)
    }

    func cachedImage(for item: ProjectItem) -> NSImage? {
        let url = fileURL(for: item)
        if let cached = originalImageStore.cached(for: url) { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        #if DEBUG
        CanvasMetrics.imageLoadCount += 1
        if let rep = img.representations.first(where: { $0 is NSBitmapImageRep }) ?? img.representations.first {
            CanvasMetrics.imageLoadBytesEstimate += rep.pixelsWide * rep.pixelsHigh * 4
        }
        #endif
        return img
    }

    func loadImage(for item: ProjectItem) async -> NSImage? {
        let url = fileURL(for: item)
        return await originalImageStore.loadIfNeeded(url: url)
    }

    func thumbnail(for item: ProjectItem) -> NSImage? {
        thumbnailStore.thumbnail(for: item, originalURL: fileURL(for: item))
    }

    func ordinalForItem(_ item: ProjectItem, in projectID: UUID) -> Int {
        let sorted = items
            .filter { $0.projectID == projectID }
            .sorted { $0.createdAt < $1.createdAt }
        return (sorted.firstIndex(of: item) ?? 0) + 1
    }

    func addTag(_ tag: String, to itemID: UUID) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        guard !items[idx].tags.contains(trimmed) else { return }
        items[idx].tags.append(trimmed)
        saveState()
    }

    func removeTag(_ tag: String, from itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].tags.removeAll { $0 == tag }
        saveState()
    }

    func setTags(_ tags: [String], for itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        saveState()
    }

    // MARK: - Selection

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
