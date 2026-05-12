import AppKit
import Foundation

extension DraftCanvasViewModel {
    func exportItem(_ item: ProjectItem) {
        guard let project = projects.first(where: { $0.id == item.projectID }) else { return }
        let ordinal = ordinalForItem(item, in: item.projectID)
        let base = ExportNaming.baseFilename(forProjectName: project.name, ordinal: ordinal)
        let fileURL = projectStore.resolvedFileURL(for: item)
        var originalSize = CGSize(width: 1024, height: 1024)
        if let data = try? Data(contentsOf: fileURL),
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? CGFloat)
                ?? (props[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? 1024
            let h = (props[kCGImagePropertyPixelHeight] as? CGFloat)
                ?? (props[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? 1024
            originalSize = CGSize(width: w, height: h)
        }
        let svgURL = item.svgFileURL(in: projectStore.rootDirectory)
        let hasVectorSVG = item.hasSVG && FileManager.default.fileExists(atPath: svgURL.path)
        exportRequest = ExportRequest(
            source: .singleItem(item),
            originalSize: originalSize,
            hasVectorSVG: hasVectorSVG,
            baseFilename: base
        )
    }

    func exportSelected() {
        guard let job = selectedJob, let pngData = job.imageData else { return }
        let projectName = projects.first(where: { $0.id == selectedProjectID })?.name ?? "Untitled"
        let base = ExportNaming.baseFilename(forProjectName: projectName, ordinal: job.index + 1)
        var originalSize = CGSize(width: 1024, height: 1024)
        if let src = CGImageSourceCreateWithData(pngData as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? CGFloat)
                ?? (props[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? 1024
            let h = (props[kCGImagePropertyPixelHeight] as? CGFloat)
                ?? (props[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? 1024
            originalSize = CGSize(width: w, height: h)
        }
        exportRequest = ExportRequest(
            source: .currentJob(pngData: pngData, baseFilename: base),
            originalSize: originalSize,
            hasVectorSVG: false,
            baseFilename: base
        )
    }

    func performExport(request: ExportRequest, settings: ExportSettings) {
        guard let saveFolder = preferredSaveFolder else {
            chooseSaveFolder()
            return
        }
        exportRequest = nil
        switch request.source {
        case .singleItem(let item): exportingProjectID = item.projectID
        case .currentJob: exportingProjectID = selectedProjectID
        case .batchItems: exportingProjectID = selectedProjectID
        }

        let base = request.baseFilename
        let stem = (base as NSString).pathExtension.isEmpty
            ? base
            : (base as NSString).deletingPathExtension
        let destination = ensureUniqueURL(
            saveFolder.appendingPathComponent("\(stem).\(settings.format.fileExtension)")
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.exportingProjectID = nil }
            do {
                try await ExportPipeline.run(
                    request: request,
                    settings: settings,
                    destination: destination,
                    projectStore: self.projectStore
                ) { [weak self] msg in
                    Task { @MainActor [weak self] in self?.logs.append(msg) }
                }
                self.logs.append("エクスポートしました: \(destination.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                self.logs.append("エクスポートに失敗しました: \(error.localizedDescription)")
                self.errorToast = "エクスポートに失敗しました"
            }
        }
    }

    func exportSelectedBatch() {
        guard !selectedItemIDs.isEmpty else { return }
        let projectName: String
        let orderedItems: [ProjectItem]
        if let smartID = selectedSmartProjectID,
           let smart = smartProjects.first(where: { $0.id == smartID }) {
            projectName = smart.name
            orderedItems = displayedItems.filter { selectedItemIDs.contains($0.id) }
        } else {
            guard let project = projects.first(where: { $0.id == selectedProjectID }) else { return }
            projectName = project.name
            orderedItems = itemsForSelectedProject.filter { selectedItemIDs.contains($0.id) }
        }
        let entries = orderedItems.map { item -> BatchExportEntry in
            let ordinal = ordinalForItem(item, in: item.projectID)
            return BatchExportEntry(
                item: item,
                ordinal: ordinal,
                baseFilename: ExportNaming.baseFilename(forProjectName: projectName, ordinal: ordinal)
            )
        }
        let allHaveVectorSVG = entries.allSatisfy {
            $0.item.hasSVG && FileManager.default.fileExists(atPath: $0.item.svgFileURL(in: projectStore.rootDirectory).path)
        }
        exportRequest = ExportRequest(
            source: .batchItems(entries),
            originalSize: .zero,
            hasVectorSVG: allHaveVectorSVG,
            baseFilename: ExportNaming.sanitize(projectName)
        )
    }

    func performBatchExport(request: ExportRequest, settings: ExportSettings) {
        guard case .batchItems(let entries) = request.source, !entries.isEmpty else { return }
        exportRequest = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let projectName = projects.first(where: { $0.id == selectedProjectID })?.name ?? "Untitled"
        panel.nameFieldStringValue = "\(ExportNaming.sanitize(projectName))-batch.zip"
        if let folder = preferredSaveFolder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let zipURL = panel.url else { return }

        batchExportProgress = (done: 0, total: entries.count)
        let store = projectStore
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ZipExportPipeline.run(
                    entries: entries,
                    settings: settings,
                    zipDestination: zipURL,
                    projectStore: store,
                    progress: { [weak self] done, total in
                        Task { @MainActor [weak self] in
                            self?.batchExportProgress = (done: done, total: total)
                        }
                    },
                    logger: { [weak self] msg in
                        Task { @MainActor [weak self] in self?.logs.append(msg) }
                    }
                )
                self.batchExportProgress = nil
                self.clearMultiSelection()
                self.isSelectionMode = false
                self.logs.append("一括エクスポートしました: \(zipURL.lastPathComponent) (\(entries.count)枚)")
                NSWorkspace.shared.activateFileViewerSelecting([zipURL])
            } catch {
                self.batchExportProgress = nil
                self.logs.append("一括エクスポートに失敗しました: \(error.localizedDescription)")
                self.errorToast = "一括エクスポートに失敗しました"
            }
        }
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "生成物を保存するときの既定フォルダを選択してください。"
        panel.directoryURL = preferredSaveFolder

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            try preferredSaveFolderStore.save(directory)
            preferredSaveFolder = directory
            logs.append("保存先フォルダを設定しました: \(directory.path)")
        } catch {
            logs.append("保存先フォルダの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    func ensureUniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for n in 1...999 {
            let candidate = dir.appendingPathComponent("\(stem) (\(n)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
