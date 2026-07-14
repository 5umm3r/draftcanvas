import Foundation

// TODO: Sendable 整理

final class ProjectStore: @unchecked Sendable {
    let rootDirectory: URL

    private var itemFileExtensions: [UUID: String] = [:]
    private let itemFileExtensionsLock = NSLock()

    func resolvedFileURL(for item: ProjectItem) -> URL {
        itemFileExtensionsLock.lock()
        let ext = itemFileExtensions[item.id] ?? "png"
        itemFileExtensionsLock.unlock()
        return itemsDirectory.appendingPathComponent("\(item.id.uuidString).\(ext)")
    }

    private var metadataURL: URL {
        rootDirectory.appendingPathComponent("projects.json")
    }

    var itemsDirectory: URL {
        rootDirectory.appendingPathComponent("items", isDirectory: true)
    }

    var masksDirectory: URL {
        rootDirectory.appendingPathComponent("masks", isDirectory: true)
    }

    var attachmentsDirectory: URL {
        rootDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    @discardableResult
    func writeAttachmentData(_ data: Data, id: UUID, fileExtension: String = "png") throws -> URL {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let url = attachmentsDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanupAttachment(id: UUID) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(id.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cleanupAllAttachments() {
        try? FileManager.default.removeItem(at: attachmentsDirectory)
    }

    @discardableResult
    func writeMaskData(_ data: Data, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_mask.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func writeCompositeData(_ data: Data, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_composite.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func writePreviewData(_ data: Data, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_preview.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    func previewURL(id: UUID) -> URL {
        masksDirectory.appendingPathComponent("\(id.uuidString)_preview.png")
    }

    @discardableResult
    func writeStrokesData(_ strokes: [MaskStroke], id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_strokes.json")
        let data = try JSONEncoder().encode(strokes)
        try data.write(to: url, options: .atomic)
        return url
    }

    func readStrokesData(id: UUID) -> [MaskStroke]? {
        let url = masksDirectory.appendingPathComponent("\(id.uuidString)_strokes.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([MaskStroke].self, from: data)
    }

    @discardableResult
    func writeSketchStrokesData(_ strokes: [SketchStroke], id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let url = attachmentsDirectory.appendingPathComponent("\(id.uuidString)_strokes.json")
        let data = try JSONEncoder().encode(strokes)
        try data.write(to: url, options: .atomic)
        return url
    }

    func readSketchStrokesData(id: UUID) -> [SketchStroke]? {
        let url = attachmentsDirectory.appendingPathComponent("\(id.uuidString)_strokes.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([SketchStroke].self, from: data)
    }

    @discardableResult
    func saveSketchSource(from sourcePath: String, itemID: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        let dst = masksDirectory.appendingPathComponent("\(itemID.uuidString)_sketch.png")
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: dst)
        return dst
    }

    func cleanupMaskFiles(id: UUID) {
        let base = id.uuidString
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(base)_mask.png"))
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(base)_composite.png"))
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(base)_preview.png"))
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(base)_strokes.json"))
        try? FileManager.default.removeItem(at: masksDirectory.appendingPathComponent("\(base)_sketch.png"))
    }

    private func cropParametersURL(id: UUID) -> URL {
        attachmentsDirectory.appendingPathComponent("\(id.uuidString)_crop.json")
    }

    @discardableResult
    func writeCropParameters(_ params: CropParameters, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let url = cropParametersURL(id: id)
        let data = try JSONEncoder().encode(params)
        try data.write(to: url, options: .atomic)
        return url
    }

    func readCropParameters(id: UUID) -> CropParameters? {
        guard let data = try? Data(contentsOf: cropParametersURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(CropParameters.self, from: data)
    }

    func cleanupCropFiles(id: UUID) {
        try? FileManager.default.removeItem(at: cropParametersURL(id: id))
    }

    let isInUbiquityContainer: Bool

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
        self.isInUbiquityContainer = rootDirectory.path.contains("/Mobile Documents/")
            || rootDirectory.path.contains("/CloudDocs/")
        indexExistingItemFiles()
    }

    private func indexExistingItemFiles() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: itemsDirectory, includingPropertiesForKeys: nil
        ) else { return }
        var map: [UUID: String] = [:]
        for url in contents {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard let id = UUID(uuidString: stem) else { continue }
            guard ext != "svg" else { continue }
            // 既存PNG優先（後方互換）
            if let existing = map[id], existing == "png" { continue }
            map[id] = ext.isEmpty ? "png" : ext
        }
        itemFileExtensionsLock.lock()
        itemFileExtensions = map
        itemFileExtensionsLock.unlock()
    }

    /// 直近の load() がデコード失敗（破損）で空スナップショットを返したか。
    /// メインスレッドからの load() 直後に参照する想定。
    private(set) var lastLoadDataWasCorrupted = false

    func load() -> Snapshot {
        lastLoadDataWasCorrupted = false
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return Snapshot()
        }
        if isInUbiquityContainer {
            resolveConflictsIfNeeded(at: metadataURL)
        }
        guard let data = coordinatedRead(at: metadataURL) else {
            return Snapshot()
        }
        guard let snapshot = try? JSONDecoder.projectDecoder.decode(Snapshot.self, from: data) else {
            // 1レコードの破損で全件消失に見える事故を防ぐため、
            // 元データを保全してから空で起動する
            backUpCorruptedMetadata(data)
            lastLoadDataWasCorrupted = true
            return Snapshot()
        }
        return snapshot
    }

    private func backUpCorruptedMetadata(_ data: Data) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = rootDirectory.appendingPathComponent("projects.json.corrupted-\(stamp)")
        try? data.write(to: backupURL, options: .atomic)
    }

    /// - Returns: 書き込みに成功したか（内容不変のスキップは成功扱い）
    @discardableResult
    func save(_ snapshot: Snapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.projectEncoder.encode(snapshot)
            return coordinatedWrite(data, to: metadataURL)
        } catch {
            return false
        }
    }

    private func coordinatedRead(at url: URL) -> Data? {
        guard isInUbiquityContainer else {
            return try? Data(contentsOf: url)
        }
        var result: Data?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordURL in
            result = try? Data(contentsOf: coordURL)
        }
        return result
    }

    @discardableResult
    private func coordinatedWrite(_ data: Data, to url: URL) -> Bool {
        // 内容が既存ファイルと同一なら書き込まない。
        // atomic 書き込みは内容不変でも mtime を更新し、iCloud の不要な再同期を誘発するため。
        if let existing = try? Data(contentsOf: url), existing == data {
            return true
        }
        guard isInUbiquityContainer else {
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        var coordinatorError: NSError?
        var didWrite = false
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordURL in
            do {
                try data.write(to: coordURL, options: .atomic)
                didWrite = true
            } catch {
                didWrite = false
            }
        }
        return didWrite && coordinatorError == nil
    }

    private func resolveConflictsIfNeeded(at url: URL) {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }
        // マージは行わないが、負けた側のバージョンをローカルに退避してから削除する。
        // マルチデバイス同時編集で片方の変更が黙って消える事故の復旧手段を残すため。
        // 退避先は再同期を誘発しないようローカルの Application Support 配下。
        let backupDir = ProjectStore.localDefaultRootDirectory()
            .appendingPathComponent("conflict-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for (index, version) in conflicts.enumerated() {
            let dst = backupDir.appendingPathComponent("projects-\(stamp)-\(index).json")
            try? FileManager.default.copyItem(at: version.url, to: dst)
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    @discardableResult
    func writeItemData(_ data: Data, for item: ProjectItem) throws -> URL {
        try writeItemData(data, for: item, fileExtension: "png")
    }

    @discardableResult
    func writeItemData(_ data: Data, for item: ProjectItem, fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let ext = fileExtension.lowercased()
        itemFileExtensionsLock.lock()
        let oldExt = itemFileExtensions[item.id]
        itemFileExtensions[item.id] = ext
        itemFileExtensionsLock.unlock()
        if let oldExt, oldExt != ext {
            try? FileManager.default.removeItem(
                at: itemsDirectory.appendingPathComponent("\(item.id.uuidString).\(oldExt)")
            )
        }
        let url = itemsDirectory.appendingPathComponent("\(item.id.uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .draftCanvasICloudLocalWrite, object: nil)
        return url
    }

    func copyItemFile(from src: ProjectItem, to dst: ProjectItem) throws {
        let srcURL = resolvedFileURL(for: src)
        let ext = srcURL.pathExtension.isEmpty ? "png" : srcURL.pathExtension.lowercased()
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let dstURL = itemsDirectory.appendingPathComponent("\(dst.id.uuidString).\(ext)")
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
        itemFileExtensionsLock.lock()
        itemFileExtensions[dst.id] = ext
        itemFileExtensionsLock.unlock()
    }

    @discardableResult
    func writeSVGData(_ data: Data, for item: ProjectItem) throws -> URL {
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let url = item.svgFileURL(in: rootDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteItemFile(_ item: ProjectItem) {
        try? FileManager.default.removeItem(at: resolvedFileURL(for: item))
        itemFileExtensionsLock.lock()
        itemFileExtensions.removeValue(forKey: item.id)
        itemFileExtensionsLock.unlock()
        if item.hasSVG {
            try? FileManager.default.removeItem(at: item.svgFileURL(in: rootDirectory))
        }
    }

    /// item 削除時の全関連ファイルを一括削除する。
    /// items/<id>.* + SVG + masks/<id>_* + attachments/<id>_* を対象とする。
    func deleteAllFiles(for item: ProjectItem) {
        deleteItemFile(item)
        cleanupMaskFiles(id: item.id)
        cleanupAttachment(id: item.id)
    }

    /// items/, masks/, attachments/ から knownItemIDs に含まれない UUID prefix を
    /// 持つファイルを削除する。過去のバグで残った orphan の掃除用途。
    @discardableResult
    func pruneOrphanFiles(knownItemIDs: Set<UUID>) -> (count: Int, bytes: Int64) {
        var total: (count: Int, bytes: Int64) = (0, 0)
        for dir in [itemsDirectory, masksDirectory, attachmentsDirectory] {
            let r = pruneOrphans(in: dir, knownItemIDs: knownItemIDs)
            total.count += r.count
            total.bytes += r.bytes
            // itemFileExtensions map からも orphan エントリを除去
            if dir == itemsDirectory {
                itemFileExtensionsLock.lock()
                itemFileExtensions = itemFileExtensions.filter { knownItemIDs.contains($0.key) }
                itemFileExtensionsLock.unlock()
            }
        }
        return total
    }

    private func pruneOrphans(in dir: URL, knownItemIDs: Set<UUID>) -> (count: Int, bytes: Int64) {
        Self.pruneOrphansStatic(in: dir, knownItemIDs: knownItemIDs)
    }

    static func pruneOrphansStatic(in dir: URL, knownItemIDs: Set<UUID>) -> (count: Int, bytes: Int64) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []
        ) else { return (0, 0) }
        var count = 0
        var bytes: Int64 = 0
        for url in contents {
            let name = url.lastPathComponent
            guard name.count >= 36,
                  let id = UUID(uuidString: String(name.prefix(36))) else { continue }
            if knownItemIDs.contains(id) { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if (try? FileManager.default.removeItem(at: url)) != nil {
                count += 1
                bytes += size
            }
        }
        return (count, bytes)
    }

    /// 任意のルート配下 (items/masks/attachments/items/.thumbs/items/.thumbs.nosync) を全部走査。
    /// iCloud 有効時のローカル (Application Support) 側 orphan 掃除にも使う。
    static func pruneOrphansUnder(root: URL, knownItemIDs: Set<UUID>) -> (count: Int, bytes: Int64) {
        let items = root.appendingPathComponent("items", isDirectory: true)
        let dirs: [URL] = [
            items,
            root.appendingPathComponent("masks", isDirectory: true),
            root.appendingPathComponent("attachments", isDirectory: true),
            items.appendingPathComponent(".thumbs", isDirectory: true),
            items.appendingPathComponent(".thumbs.nosync", isDirectory: true),
        ]
        var total: (count: Int, bytes: Int64) = (0, 0)
        for dir in dirs {
            let r = pruneOrphansStatic(in: dir, knownItemIDs: knownItemIDs)
            total.count += r.count
            total.bytes += r.bytes
        }
        return total
    }

    static func defaultRootDirectory() -> URL {
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"),
           let container = ICloudSyncMonitor.iCloudContainerURL() {
            return container
        }
        return localDefaultRootDirectory()
    }

    static func localDefaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Draft Canvas", isDirectory: true)
    }

    static func migrateToICloudIfNeeded(iCloudRoot: URL) {
        let migrationKey = "draftcanvas.migration.iCloudSync.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let fm = FileManager.default
        let localRoot = localDefaultRootDirectory()
        guard fm.fileExists(atPath: localRoot.path) else { return }

        try? fm.createDirectory(at: iCloudRoot, withIntermediateDirectories: true)

        let iCloudMetaURL = iCloudRoot.appendingPathComponent("projects.json")
        let localMetaURL = localRoot.appendingPathComponent("projects.json")

        if !fm.fileExists(atPath: iCloudMetaURL.path) {
            // iCloud 空 → ローカル全体をコピー
            for name in ["projects.json", "items", "masks", "prompt_history.json", "prompt_templates.json"] {
                let src = localRoot.appendingPathComponent(name)
                let dst = iCloudRoot.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try? fm.copyItem(at: src, to: dst)
            }
        } else {
            // iCloud に既存データあり → ローカル固有データをマージ
            mergeLocalIntoICloud(localRoot: localRoot, iCloudRoot: iCloudRoot)
        }
    }

    private static func mergeLocalIntoICloud(localRoot: URL, iCloudRoot: URL) {
        let fm = FileManager.default
        let localStore = ProjectStore(rootDirectory: localRoot)
        let iCloudStore = ProjectStore(rootDirectory: iCloudRoot)

        let localSnapshot = localStore.load()
        var cloudSnapshot = iCloudStore.load()

        let cloudProjectIDs = Set(cloudSnapshot.projects.map(\.id))
        let cloudItemIDs = Set(cloudSnapshot.items.map(\.id))
        let cloudFilteringIDs = Set(cloudSnapshot.filteringProjects.map(\.id))

        // ローカル固有プロジェクト追加
        for project in localSnapshot.projects where !cloudProjectIDs.contains(project.id) {
            cloudSnapshot.projects.append(project)
        }

        // ローカル固有アイテム追加 + 画像ファイルコピー
        for item in localSnapshot.items where !cloudItemIDs.contains(item.id) {
            cloudSnapshot.items.append(item)
            let srcURL = localStore.resolvedFileURL(for: item)
            if fm.fileExists(atPath: srcURL.path) {
                let dstDir = iCloudRoot.appendingPathComponent("items", isDirectory: true)
                try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
                let dstURL = dstDir.appendingPathComponent(srcURL.lastPathComponent)
                try? fm.copyItem(at: srcURL, to: dstURL)
            }
            // SVG
            if item.hasSVG {
                let svgSrc = item.svgFileURL(in: localRoot)
                let svgDst = item.svgFileURL(in: iCloudRoot)
                if fm.fileExists(atPath: svgSrc.path) {
                    try? fm.copyItem(at: svgSrc, to: svgDst)
                }
            }
        }

        // ローカル固有フィルタリングプロジェクト追加
        for fp in localSnapshot.filteringProjects where !cloudFilteringIDs.contains(fp.id) {
            cloudSnapshot.filteringProjects.append(fp)
        }

        // マスクファイルをコピー（UUID重複しないのでそのまま）
        let localMasks = localRoot.appendingPathComponent("masks", isDirectory: true)
        let cloudMasks = iCloudRoot.appendingPathComponent("masks", isDirectory: true)
        if fm.fileExists(atPath: localMasks.path) {
            try? fm.createDirectory(at: cloudMasks, withIntermediateDirectories: true)
            if let contents = try? fm.contentsOfDirectory(at: localMasks, includingPropertiesForKeys: nil) {
                for src in contents {
                    let dst = cloudMasks.appendingPathComponent(src.lastPathComponent)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
            }
        }

        iCloudStore.save(cloudSnapshot)
    }
}
