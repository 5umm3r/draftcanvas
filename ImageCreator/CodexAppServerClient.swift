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

private struct JSONResponse: @unchecked Sendable {
    let value: [String: Any]
}

private struct SendableParams: @unchecked Sendable {
    let value: [String: Any]?
}

final class CodexAppServerClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.imagecreator.codex-app-server")
    let codexExecutablePath: String
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutParser = JSONLineParser()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONResponse, Error>] = [:]
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

        do {
            try await task.value
        } catch {
            queue.sync { self.startupTask = nil }
            throw error
        }
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

    static func fetchVersion(executablePath: String) async -> String? {
        await withCheckedContinuation { continuation in
            let config = CodexLaunchConfiguration.resolve(codexExecutablePath: executablePath)
            let versionArgs: [String]
            if let first = config.arguments.first {
                versionArgs = [first, "--version"]
            } else {
                versionArgs = ["--version"]
            }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: config.executablePath)
            process.arguments = versionArgs
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                let trimmed = raw
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                continuation.resume(returning: trimmed?.isEmpty == false ? trimmed : nil)
            } catch {
                continuation.resume(returning: nil)
            }
        }
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

    func startThread(
        model: String,
        reasoningEffort: String,
        instructions: String? = nil,
        disableResponseStorage: Bool = false
    ) async throws -> String {
        var params: [String: Any] = [
            "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "ephemeral": true,
            "experimentalRawEvents": true,
            "persistExtendedHistory": false,
            "serviceName": "Image Creator",
            "model": model,
            "config": [
                "model_reasoning_effort": reasoningEffort,
                "max_output_tokens": 800
            ]
        ]
        if let instructions {
            params["instructions"] = instructions
        }
        if disableResponseStorage {
            params["disableResponseStorage"] = true
        }
        let response = try await sendRequest(method: "thread/start", params: params)

        guard
            let thread = response["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        else {
            throw ImageCreatorError.missingThreadID
        }
        return threadID
    }

    func listModels(includeHidden: Bool = false) async throws -> [CodexModel] {
        try await start()
        let response = try await sendRequest(
            method: "model/list",
            params: ["includeHidden": includeHidden]
        )
        guard let data = response["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { dict -> CodexModel? in
            guard
                let id = dict["id"] as? String,
                let displayName = dict["displayName"] as? String
            else { return nil }
            let efforts = (dict["supportedReasoningEfforts"] as? [[String: Any]])?
                .compactMap { $0["reasoningEffort"] as? String } ?? []
            let defaultEffort = dict["defaultReasoningEffort"] as? String ?? "medium"
            let isDefault = dict["isDefault"] as? Bool ?? false
            let rating = ModelRating.lookup(displayName: displayName)
            print("[ModelRating] id=\(id) displayName=\(displayName) rating=\(String(describing: rating))")
            return CodexModel(
                id: id,
                displayName: displayName,
                supportedReasoningEfforts: efforts,
                defaultReasoningEffort: defaultEffort,
                isDefault: isDefault,
                rating: rating
            )
        }
    }

    func runTurn(threadID: String, prompt: String, referenceImagePath: String? = nil) async throws -> CodexTurnResult {
        let waiter = TurnWaiter(threadID: threadID)

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
                "input": CodexTurnInputFactory.input(prompt: prompt, referenceImagePath: referenceImagePath)
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
        let sendableParams = SendableParams(value: params)
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONResponse, Error>) in
            queue.async {
                guard let stdinHandle = self.stdinHandle, self.process?.isRunning == true else {
                    continuation.resume(throwing: ImageCreatorError.processNotRunning)
                    return
                }

                let id = self.nextRequestID
                self.nextRequestID += 1
                self.pending[id] = continuation

                do {
                    let request = JSONRPCRequest(id: id, method: method, params: sendableParams.value)
                    let line = try JSONRPCCodec.encodeRequestLine(request)
                    self.emitLog("-> \(String(data: line, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? method)")
                    try stdinHandle.write(contentsOf: line)
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
        return response.value
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
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.queue.async {
                self.handleStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.emitLog("stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.handleProcessExit()
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
            continuation.resume(returning: JSONResponse(value: result))
        } else {
            continuation.resume(returning: JSONResponse(value: [:]))
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
        if let found = Self.findExecutable("codex") {
            return found
        }
        return "codex"
    }

    private static func findExecutable(_ name: String) -> String? {
        if let path = findViaLoginShell(name) {
            return path
        }
        return searchCommonPaths(for: name)
    }

    private static func findViaLoginShell(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "which \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let lines = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.hasPrefix("/") }
            return lines.last
        } catch {
            return nil
        }
    }

    private static func searchCommonPaths(for name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] ?? "\(home)/.nvm"
        let nvmVersionsDir = "\(nvmDir)/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) {
            for version in versions.sorted().reversed() {
                let path = "\(nvmVersionsDir)/\(version)/bin/\(name)"
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.volta/bin"] {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}

enum CodexTurnInputFactory {
    static func input(prompt: String, referenceImagePath: String? = nil) -> [[String: Any]] {
        var input: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt,
                "text_elements": []
            ]
        ]

        if let referenceImagePath {
            input.append([
                "type": "localImage",
                "path": referenceImagePath
            ])
        }

        return input
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

private final class TurnWaiter: @unchecked Sendable {
    let threadID: String
    var continuation: CheckedContinuation<CodexTurnResult, Error>?
    private var imageResult: CodexImageResult?
    private var assistantText = ""
    private var logs: [String] = []
    private var didFinish = false

    init(threadID: String) {
        self.threadID = threadID
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

        let result = CodexTurnResult(
            imageResult: imageResult,
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
