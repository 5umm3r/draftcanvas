import Foundation

enum BinaryRunner {
    enum Failure: Error, LocalizedError {
        case binaryNotFound(String)
        case timeout
        case nonZeroExit(Int32, String)
        case io(Error)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let name): return String(localized: "バイナリが見つかりません: \(name)")
            case .timeout: return String(localized: "処理がタイムアウトしました")
            case .nonZeroExit(let code, let err): return String(localized: "終了コード \(code): \(err)")
            case .io(let e): return String(localized: "IO エラー: \(e.localizedDescription)")
            }
        }
    }

    static func resolve(name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") else {
            throw Failure.binaryNotFound(name)
        }
        return url
    }

    static func run(
        binary: String,
        arguments: [String],
        timeout: TimeInterval = 120,
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> (stdout: Data, stderr: String) {
        let url = try resolve(name: binary)
        let p = Process()
        p.executableURL = url
        p.arguments = arguments

        // stdout は不要（oxipng/pngquant はファイル出力）→ /dev/null で cooperative thread ブロック回避
        p.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        p.standardError = errPipe

        // stderr はパイプバッファ（約64KB）が埋まると子プロセスの write が
        // ブロックして終了しなくなるため、実行中に随時ドレインする
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
            throw Failure.io(error)
        }

        // terminationHandler で非ブロッキング待機（cooperative thread pool を消費しない）
        let status: Int32 = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    p.terminationHandler = { proc in
                        continuation.resume(returning: proc.terminationStatus)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if p.isRunning { p.terminate() }
                throw Failure.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        // 残りの stderr を回収
        errPipe.fileHandleForReading.readabilityHandler = nil
        if let trailing = try? errPipe.fileHandleForReading.readToEnd() {
            stderrCollector.append(trailing)
        }
        let stderr = stderrCollector.text

        guard allowedExitCodes.contains(status) else {
            throw Failure.nonZeroExit(status, stderr)
        }
        return (Data(), stderr)
    }
}

/// readabilityHandler（バックグラウンドキュー）から蓄積されるパイプ出力の
/// スレッドセーフな収集バッファ
final class PipeTextCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
