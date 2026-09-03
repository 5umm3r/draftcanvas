import AppKit
import Foundation

extension DraftCanvasViewModel {

    // MARK: - Shared helpers

    func touchProject(id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].updatedAt = Date()
    }

    // MARK: - Private helpers (no saveState, no selectedItemID side-effects)

    private func performDelete(_ item: ProjectItem) {
        let url = projectStore.resolvedFileURL(for: item)
        projectStore.deleteAllFiles(for: item)
        thumbnailStore.deleteThumbnail(for: item)
        originalImageStore.evict(url: url)
        editSourceRefCounts.removeValue(forKey: item.id)
        attachmentRefCounts.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
        touchProject(id: item.projectID)
        // アクセス履歴を残すと iCloudAccessTimestamps が際限なく肥大する
        Task { [cacheEviction] in
            await cacheEviction.forgetAccess(url: url)
        }
    }

    private func performMove(_ item: ProjectItem, targetProjectID: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              items[idx].projectID != targetProjectID else { return false }
        let sourceProjectID = items[idx].projectID
        items[idx].projectID = targetProjectID
        items[idx].editedFromItemID = nil
        touchProject(id: sourceProjectID)
        touchProject(id: targetProjectID)
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
            touchProject(id: targetProjectID)
            return true
        } catch {
            logs.append("コピーエラー: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delete protection

    /// 通常表示ではブックマーク中の画像を削除不可とする。
    /// 「ブックマークのみ表示」中は整理目的と見なし、すべて削除可能。
    func canDeleteItem(_ item: ProjectItem) -> Bool {
        canvasShowsBookmarkedOnly || !item.isBookmarked
    }

    struct BatchDeletePlan {
        let deletableIDs: Set<UUID>
        let protectedCount: Int
    }

    func batchDeletePlan(for ids: Set<UUID>) -> BatchDeletePlan {
        let targets = items.filter { ids.contains($0.id) }
        let deletable = targets.filter { canDeleteItem($0) }
        let deletableIDs = Set(deletable.map(\.id))
        let protectedCount = targets.count - deletableIDs.count
        return BatchDeletePlan(deletableIDs: deletableIDs, protectedCount: protectedCount)
    }

    // MARK: - Single-item public API

    func deleteItem(_ item: ProjectItem) {
        guard canDeleteItem(item) else { return }
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
            touchProject(id: item.projectID)
            saveState()
        } catch {
            showError("アイテムの複製に失敗しました")
            logs.append("複製エラー: \(error.localizedDescription)")
        }
    }

    func copyItemToProject(_ item: ProjectItem, targetProjectID: UUID) {
        if !performCopy(item, targetProjectID: targetProjectID) {
            showError("アイテムのコピーに失敗しました")
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
        let plan = batchDeletePlan(for: ids)
        let targets = items.filter { plan.deletableIDs.contains($0.id) }
        for item in targets {
            performDelete(item)
        }
        if let sel = selectedItemID, plan.deletableIDs.contains(sel) { selectedItemID = nil }
        selectedItemIDs.subtract(plan.deletableIDs)
        saveState()
        return plan.protectedCount
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

    /// 過去のバグや異常終了で残った orphan ファイルを掃除する。
    /// メタデータ items[] に存在しない UUID prefix のファイルを items/masks/attachments/.thumbs から削除。
    /// iCloud 有効時は iCloud container + Application Support 側 (旧ローカルコピー) の両方を掃除する。
    @discardableResult
    func pruneOrphanFiles() -> (count: Int, bytes: Int64) {
        let knownIDs = Set(items.map(\.id))
        var total = projectStore.pruneOrphanFiles(knownItemIDs: knownIDs)
        let t = thumbnailStore.pruneOrphanFiles(knownItemIDs: knownIDs)
        total.count += t.count
        total.bytes += t.bytes
        if projectStore.isInUbiquityContainer {
            let localRoot = ProjectStore.localDefaultRootDirectory()
            if localRoot != projectStore.rootDirectory,
               FileManager.default.fileExists(atPath: localRoot.path) {
                let l = ProjectStore.pruneOrphansUnder(root: localRoot, knownItemIDs: knownIDs)
                total.count += l.count
                total.bytes += l.bytes
            }
        }
        // ~/.codex/generated_images/<threadID>/ の掃除
        // DraftCanvas 経由の Codex 生成画像は items/ にコピー済みなので元は不要
        let c = CodexGeneratedImageFallbackLoader.pruneAll()
        total.count += c.count
        total.bytes += c.bytes
        return total
    }

    @discardableResult
    func copyItemToClipboard(_ item: ProjectItem) async -> Bool {
        let url = fileURL(for: item)
        guard
            let imageData = try? await imageLoader.loadData(at: url, syncMonitor: syncMonitor),
            let image = NSImage(data: imageData)
        else { return false }
        await cacheEviction.recordAccess(url: url)
        ImageClipboard.copy(imageData: imageData, image: image)
        return true
    }

    func fileURL(for item: ProjectItem) -> URL {
        projectStore.resolvedFileURL(for: item)
    }

    /// メモリキャッシュのみを参照する。ミス時のディスク読み込みは
    /// 必ず loadImage(for:) 経由（非同期・iCloud 対応・in-flight 共有・キャッシュ書き戻し）で行う。
    /// メインスレッドでの同期フルデコードと NSImage(contentsOf:) の
    /// iCloud 未ダウンロード時ブロックを避けるため。
    func cachedImage(for item: ProjectItem) -> NSImage? {
        originalImageStore.cached(for: fileURL(for: item))
    }

    func cachedImageAsync(for item: ProjectItem) async -> NSImage? {
        let url = fileURL(for: item)
        if let cached = originalImageStore.cached(for: url) { return cached }
        guard let img = try? await imageLoader.loadImage(at: url, syncMonitor: syncMonitor) else { return nil }
        await cacheEviction.recordAccess(url: url)
        return img
    }

    func loadImage(for item: ProjectItem) async -> NSImage? {
        let url = fileURL(for: item)
        return await originalImageStore.loadIfNeeded(url: url, syncMonitor: syncMonitor)
    }

    func thumbnail(for item: ProjectItem) -> NSImage? {
        thumbnailStore.thumbnail(for: item, originalURL: fileURL(for: item))
    }

    func inpaintStrokes(for itemID: UUID) -> [MaskStroke]? {
        projectStore.readStrokesData(id: itemID)
    }

    func cropParameters(for itemID: UUID) -> CropParameters? {
        projectStore.readCropParameters(id: itemID)
    }

    func inpaintPreviewPath(for itemID: UUID) -> String {
        projectStore.previewURL(id: itemID).path
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

    func toggleBookmark(_ item: ProjectItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isBookmarked.toggle()
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
