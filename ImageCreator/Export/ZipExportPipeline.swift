import Foundation

enum ZipExportPipeline {
    enum Failure: Error, LocalizedError {
        case allEntriesFailed
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .allEntriesFailed: return "全ての画像のエクスポートに失敗しました"
            case .zipFailed(let msg): return "ZIP作成に失敗しました: \(msg)"
            }
        }
    }

    static func run(
        entries: [BatchExportEntry],
        settings: ExportSettings,
        zipDestination: URL,
        projectStore: ProjectStore,
        progress: @escaping @Sendable (Int, Int) -> Void,
        logger: @escaping @Sendable (String) -> Void
    ) async throws {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("imagecreator-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let total = entries.count
        var failCount = 0

        for (i, entry) in entries.enumerated() {
            let request = ExportRequest(
                source: .singleItem(entry.item),
                originalSize: .zero,
                hasVectorSVG: entry.item.hasSVG,
                baseFilename: entry.baseFilename
            )
            let filename = "\(entry.baseFilename).\(settings.format.fileExtension)"
            let destination = stagingDir.appendingPathComponent(filename)

            do {
                try await ExportPipeline.run(
                    request: request,
                    settings: settings,
                    destination: destination,
                    projectStore: projectStore,
                    logger: logger
                )
            } catch {
                failCount += 1
                logger("スキップ [\(entry.baseFilename)]: \(error.localizedDescription)")
            }

            let done = i + 1
            progress(done, total)
        }

        guard failCount < total else { throw Failure.allEntriesFailed }

        try await runSystemZip(stagingDir: stagingDir, destination: zipDestination)
    }

    private static func runSystemZip(stagingDir: URL, destination: URL) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = ["-r", "-j", destination.path, stagingDir.path]
        let errPipe = Pipe()
        p.standardError = errPipe

        do { try p.run() } catch { throw Failure.zipFailed(error.localizedDescription) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let stderrData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    throw Failure.zipFailed("終了コード \(p.terminationStatus): \(stderr)")
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300_000_000_000) // 5分タイムアウト
                if p.isRunning { p.terminate() }
                throw Failure.zipFailed("タイムアウト")
            }
            try await group.next()!
            group.cancelAll()
        }
    }
}
