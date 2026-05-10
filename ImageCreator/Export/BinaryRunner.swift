import Foundation

enum BinaryRunner {
    enum Failure: Error, LocalizedError {
        case binaryNotFound(String)
        case timeout
        case nonZeroExit(Int32, String)
        case io(Error)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let name): return "バイナリが見つかりません: \(name)"
            case .timeout: return "処理がタイムアウトしました"
            case .nonZeroExit(let code, let err): return "終了コード \(code): \(err)"
            case .io(let e): return "IO エラー: \(e.localizedDescription)"
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
        timeout: TimeInterval = 120
    ) async throws -> (stdout: Data, stderr: String) {
        let url = try resolve(name: binary)
        let p = Process()
        p.executableURL = url
        p.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
        } catch {
            throw Failure.io(error)
        }

        return try await withThrowingTaskGroup(of: (Data, String).self) { group in
            group.addTask {
                p.waitUntilExit()
                let stdout = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderrData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                guard p.terminationStatus == 0 else {
                    throw Failure.nonZeroExit(p.terminationStatus, stderr)
                }
                return (stdout, stderr)
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
    }
}
