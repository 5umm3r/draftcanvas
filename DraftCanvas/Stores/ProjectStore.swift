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

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
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

    func load() -> Snapshot {
        guard
            FileManager.default.fileExists(atPath: metadataURL.path),
            let data = try? Data(contentsOf: metadataURL)
        else {
            return Snapshot()
        }
        guard let snapshot = try? JSONDecoder.projectDecoder.decode(Snapshot.self, from: data) else {
            return Snapshot()
        }

        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.projectEncoder.encode(snapshot) {
            try? data.write(to: metadataURL, options: .atomic)
        }
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

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Draft Canvas", isDirectory: true)
    }
}
