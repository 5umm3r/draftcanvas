import Foundation

struct CodexLaunchConfiguration {
    let executablePath: String
    let arguments: [String]
    let environmentPath: String

    static func resolve(codexExecutablePath: String) -> CodexLaunchConfiguration {
        let codexURL = URL(fileURLWithPath: codexExecutablePath)
        let binDirectory = codexURL.deletingLastPathComponent().path
        let siblingNode = URL(fileURLWithPath: binDirectory).appendingPathComponent("node").path
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let environmentPath = "\(binDirectory):\(inheritedPath)"

        if codexURL.lastPathComponent == "codex" {
            return CodexLaunchConfiguration(
                executablePath: siblingNode,
                arguments: [codexExecutablePath, "app-server", "--listen", "stdio://"],
                environmentPath: environmentPath
            )
        }

        return CodexLaunchConfiguration(
            executablePath: "/usr/bin/env",
            arguments: ["codex", "app-server", "--listen", "stdio://"],
            environmentPath: environmentPath
        )
    }
}

final class CodexAppServerClient {
    private let queue = DispatchQueue(label: "local.imagecreator.codex-app-server")
    private let codexExecutablePath: String
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutParser = JSONLineParser()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var turnWaiters: [String: TurnWaiter] = [:]
    private var startupTask: Task<Void, Error>?
    var onLog: (@Sendable (String) -> Void)?

    init(codexExecutablePath: String = CodexAppServerClient.defaultCodexExecutablePath()) {
        self.codexExecutablePath = codexExecutablePath
    }

    deinit {
        stop()
    }

    func start() async throws {
        let task = queue.sync { () -> Task<Void, Error> in
            if let startupTask {
                return startupTask
            }

            let task = Task {
                try await self.performStart()
            }
            startupTask = task
            return task
        }

        try await task.value
    }

    private func performStart() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.process?.isRunning == true {
                    continuation.resume()
                    return
                }

                do {
                    try self.launchProcess()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        _ = try await sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "image-creator",
                    "title": "Image Creator",
                    "version": "1.0.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        )
    }

    func stop() {
        queue.sync {
            ProcessTerminationResources.release(
                process: self.process,
                stdinHandle: self.stdinHandle,
                stdoutHandle: self.stdoutHandle,
                stderrHandle: self.stderrHandle
            )
            self.process = nil
            self.stdinHandle = nil
            self.stdoutHandle = nil
            self.stderrHandle = nil
            self.startupTask = nil
            self.pending.values.forEach { $0.resume(throwing: ImageCreatorError.processExited) }
            self.pending.removeAll()
            self.turnWaiters.values.forEach { $0.finish(throwing: ImageCreatorError.processExited) }
            self.turnWaiters.removeAll()
        }
    }

    func startThread() async throws -> String {
        let response = try await sendRequest(
            method: "thread/start",
            params: [
                "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
                "approvalPolicy": "never",
                "sandbox": "read-only",
                "ephemeral": true,
                "experimentalRawEvents": true,
                "persistExtendedHistory": false,
                "serviceName": "Image Creator"
            ]
        )

        guard
            let thread = response["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        else {
            throw ImageCreatorError.missingThreadID
        }
        return threadID
    }

    func runTurn(threadID: String, prompt: String, outputMode: GenerationOutputMode) async throws -> CodexTurnResult {
        let waiter = TurnWaiter(threadID: threadID, outputMode: outputMode)

        let resultTask = Task<CodexTurnResult, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexTurnResult, Error>) in
                queue.async {
                    self.turnWaiters[threadID] = waiter
                    waiter.continuation = continuation
                }
            }
        }

        _ = try await sendRequest(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": prompt,
                        "text_elements": []
                    ]
                ]
            ]
        )

        return try await withTimeout(seconds: 240) {
            try await resultTask.value
        }
    }

    func readAccountUsageStatus() async throws -> CodexAccountUsageStatus {
        try await start()

        let accountResponse = try await sendRequest(
            method: "account/read",
            params: [
                "refreshToken": false
            ]
        )
        let rateLimitsResponse = try await sendRequest(method: "account/rateLimits/read")

        return CodexAccountUsageStatus.parse(
            accountResponse: accountResponse,
            rateLimitsResponse: rateLimitsResponse
        )
    }

    func sendRequest(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let stdinHandle = self.stdinHandle, self.process?.isRunning == true else {
                    continuation.resume(throwing: ImageCreatorError.processNotRunning)
                    return
                }

                let id = self.nextRequestID
                self.nextRequestID += 1
                self.pending[id] = continuation

                do {
                    let request = JSONRPCRequest(id: id, method: method, params: params)
                    let line = try JSONRPCCodec.encodeRequestLine(request)
                    self.emitLog("-> \(String(data: line, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? method)")
                    try stdinHandle.write(contentsOf: line)
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func launchProcess() throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let launchConfiguration = CodexLaunchConfiguration.resolve(codexExecutablePath: codexExecutablePath)
        process.executableURL = URL(fileURLWithPath: launchConfiguration.executablePath)
        process.arguments = launchConfiguration.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = launchConfiguration.environmentPath
        process.environment = environment

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.handleStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.emitLog("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.handleProcessExit()
            }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        emitLog("codex app-server を起動しました: \(launchConfiguration.executablePath) \(launchConfiguration.arguments.joined(separator: " "))")
    }

    private func handleStdout(_ data: Data) {
        let messages = stdoutParser.append(data)
        for message in messages {
            emitLog("<- \(compactJSONString(message))")
            if let id = message["id"] as? Int {
                handleResponse(message, id: id)
            } else {
                handleNotification(message)
            }
        }
    }

    private func handleResponse(_ message: [String: Any], id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }

        if let error = message["error"] as? [String: Any] {
            let errorMessage = error["message"] as? String ?? compactJSONString(error)
            continuation.resume(throwing: ImageCreatorError.rpcError(errorMessage))
            return
        }

        if let result = message["result"] as? [String: Any] {
            continuation.resume(returning: result)
        } else {
            continuation.resume(returning: [:])
        }
    }

    private func handleNotification(_ message: [String: Any]) {
        guard let threadID = CodexEventExtractor.threadID(from: message) else {
            return
        }

        guard let waiter = turnWaiters[threadID] else {
            return
        }

        waiter.consume(message)
        if CodexEventExtractor.isTurnCompleted(message, threadID: threadID) {
            turnWaiters.removeValue(forKey: threadID)
            waiter.finish()
        }
    }

    private func handleProcessExit() {
        pending.values.forEach { $0.resume(throwing: ImageCreatorError.processExited) }
        pending.removeAll()
        turnWaiters.values.forEach { $0.finish(throwing: ImageCreatorError.processExited) }
        turnWaiters.removeAll()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        startupTask = nil
        emitLog("codex app-server が終了しました。")
    }

    private func emitLog(_ message: String) {
        onLog?(message)
    }

    private func compactJSONString(_ object: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: []),
            let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: object)
        }
        return string
    }

    private static func defaultCodexExecutablePath() -> String {
        "/Users/mbp16-max/.nvm/versions/node/v22.16.0/bin/codex"
    }
}

struct ProcessTerminationResources {
    static func release(
        process: Process?,
        stdinHandle: FileHandle?,
        stdoutHandle: FileHandle?,
        stderrHandle: FileHandle?
    ) {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdinHandle?.close()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private final class TurnWaiter {
    let threadID: String
    let outputMode: GenerationOutputMode
    var continuation: CheckedContinuation<CodexTurnResult, Error>?
    private var imageResult: CodexImageResult?
    private var assistantText = ""
    private var logs: [String] = []
    private var didFinish = false

    init(threadID: String, outputMode: GenerationOutputMode) {
        self.threadID = threadID
        self.outputMode = outputMode
    }

    func consume(_ message: [String: Any]) {
        if let result = CodexEventExtractor.extractImageResult(from: message) {
            imageResult = result
            logs.append("画像生成結果を受信しました: \(result.imageID)")
        }

        if let text = CodexEventExtractor.extractAssistantText(from: message) {
            if !assistantText.isEmpty {
                assistantText.append("\n")
            }
            assistantText.append(text)
            logs.append("assistant text を受信しました。")
        }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true

        let svgText = SVGExtractor.extract(from: assistantText)
        let result = CodexTurnResult(
            imageResult: imageResult,
            svgText: svgText,
            assistantText: assistantText,
            logs: logs
        )
        continuation?.resume(returning: result)
        continuation = nil
    }

    func finish(throwing error: Error) {
        guard !didFinish else { return }
        didFinish = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private func withTimeout<T: Sendable>(
    seconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw ImageCreatorError.rpcError("Codex turn がタイムアウトしました。")
        }

        guard let result = try await group.next() else {
            throw ImageCreatorError.rpcError("Codex turn の結果を取得できませんでした。")
        }
        group.cancelAll()
        return result
    }
}
