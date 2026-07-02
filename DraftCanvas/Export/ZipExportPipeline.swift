import Foundation

enum ZipExportPipeline {
    enum Failure: Error, LocalizedError {
        case allEntriesFailed
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .allEntriesFailed: return String(localized: "全ての画像のエクスポートに失敗しました")
            case .zipFailed(let msg): return String(localized: "ZIP作成に失敗しました: \(msg)")
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
            .appendingPathComponent("draftcanvas-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let total = entries.count
        var failCount = 0
        var doneCount = 0

        // PNG 最適化は外部プロセスを最大3回起動するため直列だと件数×起動コストが
        // 積み上がる。数件並列に制限して処理する（出力は独立ファイルで競合なし）。
        let maxConcurrent = 3
        try await withThrowingTaskGroup(of: Bool.self) { group in
            var iterator = entries.makeIterator()

            func addNext() -> Bool {
                guard let entry = iterator.next() else { return false }
                group.addTask {
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
                        return true
                    } catch {
                        logger("スキップ [\(entry.baseFilename)]: \(error.localizedDescription)")
                        return false
                    }
                }
                return true
            }

            for _ in 0..<maxConcurrent {
                if !addNext() { break }
            }
            while let succeeded = try await group.next() {
                if !succeeded { failCount += 1 }
                doneCount += 1
                progress(doneCount, total)
                _ = addNext()
            }
        }

        guard failCount < total else { throw Failure.allEntriesFailed }

        try await runSystemZip(stagingDir: stagingDir, destination: zipDestination)
    }

    private static func runSystemZip(stagingDir: URL, destination: URL) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = ["-r", "-j", destination.path, stagingDir.path]
        p.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        p.standardError = errPipe

        // パイプ詰まり防止のため stderr を実行中にドレインする
        let stderrCollector = PipeTextCollector()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrCollector.append(data)
            }
        }

        do {
            try p.run()
        } catch {
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw Failure.zipFailed(error.localizedDescription)
        }

        // waitUntilExit はスレッドを占有するため terminationHandler で非ブロッキング待機
        let status: Int32 = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    p.terminationHandler = { proc in
                        continuation.resume(returning: proc.terminationStatus)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300_000_000_000) // 5分タイムアウト
                if p.isRunning { p.terminate() }
                throw Failure.zipFailed(String(localized: "タイムアウト"))
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        errPipe.fileHandleForReading.readabilityHandler = nil
        if let trailing = try? errPipe.fileHandleForReading.readToEnd() {
            stderrCollector.append(trailing)
        }
        guard status == 0 else {
            throw Failure.zipFailed("終了コード \(status): \(stderrCollector.text)")
        }
    }
}
