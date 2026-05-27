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
    private let queue = DispatchQueue(label: "local.draftcanvas.codex-app-server")
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
                    "name": "draftcanvas",
                    "title": "Draft Canvas",
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
        queue.async {
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
            self.pending.values.forEach { $0.resume(throwing: DraftCanvasError.processExited) }
            self.pending.removeAll()
            self.turnWaiters.values.forEach { $0.finish(throwing: DraftCanvasError.processExited) }
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
            "serviceName": "Draft Canvas",
            "model": model,
            "config": [
                "model_reasoning_effort": reasoningEffort,
                "max_output_tokens": 800
            ]
        ]
        if let instructions {
            params["instructions"] = instructions
        } else {
            params["instructions"] = CodexLogFormatter.defaultThreadInstructions
        }
        if disableResponseStorage {
            params["disableResponseStorage"] = true
        }
        let response = try await sendRequest(method: "thread/start", params: params)

        guard
            let thread = response["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        else {
            throw DraftCanvasError.missingThreadID
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

    func runTurn(
        threadID: String,
        prompt: String,
        referenceImagePath: String? = nil
    ) async throws -> CodexTurnResult {
        let waiter = TurnWaiter(threadID: threadID)

        let resultTask = Task<CodexTurnResult, Error> {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexTurnResult, Error>) in
                    self.queue.async {
                        if let existing = self.turnWaiters[threadID] {
                            self.emitLog("[警告] thread ID 衝突を検出: \(threadID)。先発 waiter を中断します。")
                            existing.finish(throwing: DraftCanvasError.threadIDCollision(threadID))
                        }
                        self.turnWaiters[threadID] = waiter
                        waiter.continuation = continuation
                    }
                }
            } onCancel: {
                self.queue.async {
                    self.turnWaiters.removeValue(forKey: threadID)
                    waiter.finish(throwing: CancellationError())
                }
            }
        }

        do {
            _ = try await sendRequest(
                method: "turn/start",
                params: [
                    "threadId": threadID,
                    "input": CodexTurnInputFactory.input(prompt: prompt, referenceImagePath: referenceImagePath)
                ]
            )
        } catch {
            resultTask.cancel()
            throw error
        }

        do {
            return try await withTimeout(seconds: 480) {
                try await resultTask.value
            }
        } catch {
            resultTask.cancel()
            queue.async {
                self.turnWaiters.removeValue(forKey: threadID)
                waiter.finish(throwing: error)
            }
            throw error
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
                    continuation.resume(throwing: DraftCanvasError.processNotRunning)
                    return
                }

                let id = self.nextRequestID
                self.nextRequestID += 1
                self.pending[id] = continuation

                do {
                    let request = JSONRPCRequest(id: id, method: method, params: sendableParams.value)
                    let line = try JSONRPCCodec.encodeRequestLine(request)
                    self.emitLog(CodexLogFormatter.outbound(method: method, params: sendableParams.value))
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
        if codexExecutablePath.hasPrefix("/") {
            try CodexExecutableValidator.validate(codexExecutablePath)
        }

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
        let displayPath = launchConfiguration.executablePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        emitLog("codex app-server を起動しました: \(displayPath) \(launchConfiguration.arguments.joined(separator: " "))")
    }

    private func handleStdout(_ data: Data) {
        let messages = stdoutParser.append(data)
        for message in messages {
            if let logLine = CodexLogFormatter.inbound(message) {
                emitLog(logLine)
            }
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
            if let rateLimitError = RateLimitClassifier.classify(error) {
                continuation.resume(throwing: rateLimitError)
            } else if let freePlanError = FreePlanClassifier.classify(error) {
                continuation.resume(throwing: freePlanError)
            } else {
                let errorMessage = error["message"] as? String ?? compactJSONString(error)
                continuation.resume(throwing: DraftCanvasError.rpcError(errorMessage))
            }
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
        pending.values.forEach { $0.resume(throwing: DraftCanvasError.processExited) }
        pending.removeAll()
        turnWaiters.values.forEach { $0.finish(throwing: DraftCanvasError.processExited) }
        turnWaiters.removeAll()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        startupTask = nil
        emitLog(String(localized: "codex app-server が終了しました。"))
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

enum FreePlanClassifier {
    private static let freePlanKeywords = ["free plan", "free tier", "upgrade", "not entitled", "requires a paid", "paid plan", "subscription required"]

    static func classify(_ error: [String: Any]) -> DraftCanvasError? {
        let message = (error["message"] as? String ?? "").lowercased()
        guard freePlanKeywords.contains(where: { message.contains($0) }) else { return nil }
        return .freePlanNotEntitled(message: error["message"] as? String ?? message)
    }
}

enum RateLimitClassifier {
    private static let rateLimitKeywords = ["rate_limit", "rate limit", "too many requests", "quota"]

    static func classify(_ error: [String: Any]) -> DraftCanvasError? {
        let isRateLimitCode: Bool
        let isServiceUnavailable: Bool
        if let intCode = error["code"] as? Int {
            isRateLimitCode = intCode == 429 || intCode == -32029
            isServiceUnavailable = intCode == 503
        } else if let strCode = error["code"] as? String {
            isRateLimitCode = strCode == "429"
            isServiceUnavailable = strCode == "503"
        } else {
            isRateLimitCode = false
            isServiceUnavailable = false
        }

        let message = (error["message"] as? String ?? "").lowercased()
        let hasRateLimitKeyword = rateLimitKeywords.contains { message.contains($0) }

        guard isRateLimitCode || (!isServiceUnavailable && hasRateLimitKeyword) else { return nil }

        let retryAfter: TimeInterval? = {
            guard let data = error["data"] as? [String: Any] else { return nil }
            if let ra = data["retry_after"] as? TimeInterval { return ra }
            if let ra = data["retryAfter"] as? TimeInterval { return ra }
            if let ra = data["retry_after"] as? Int { return TimeInterval(ra) }
            if let ra = data["retryAfter"] as? Int { return TimeInterval(ra) }
            return nil
        }()

        return .rateLimited(retryAfter: retryAfter)
    }
}

enum CodexExecutableValidator {
    private static let allowedPrefixes: [String] = {
        let home = NSHomeDirectory()
        return [
            "/usr/local/",
            "/opt/homebrew/",
            "/usr/bin/",
            "/bin/",
            "\(home)/.codex/",
            "\(home)/.nvm/",
            "\(home)/.volta/",
            "\(home)/Library/",
            Bundle.main.bundlePath,
        ]
    }()

    static func validate(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw DraftCanvasError.invalidRequest("codex executable path must be absolute: \(path)")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw DraftCanvasError.invalidRequest("codex executable not found: \(path)")
        }
        guard fm.isExecutableFile(atPath: path) else {
            throw DraftCanvasError.invalidRequest("codex executable is not executable: \(path)")
        }

        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let isAllowed = allowedPrefixes.contains { prefix in
            resolvedPath.hasPrefix(prefix) || path.hasPrefix(prefix)
        }
        guard isAllowed else {
            throw DraftCanvasError.invalidRequest("codex executable path is not in an allowed location: \(path)")
        }
    }
}

#if !DEBUG
private func redactSensitiveFields(in dict: [String: Any]) -> [String: Any] {
    let sensitiveKeys: Set<String> = ["prompt", "instructions", "input", "email", "apikey", "token", "refresh_token", "accesstoken", "authorization", "password"]
    var redacted = dict
    for key in dict.keys {
        if sensitiveKeys.contains(key.lowercased()) {
            let len = (dict[key] as? String)?.count ?? 0
            redacted[key] = "[redacted len=\(len)]"
        } else if let nested = dict[key] as? [String: Any] {
            redacted[key] = redactSensitiveFields(in: nested)
        }
    }
    return redacted
}
#endif

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
            throw DraftCanvasError.timeout
        }

        guard let result = try await group.next() else {
            throw DraftCanvasError.rpcError(String(localized: "Codex turn の結果を取得できませんでした。"))
        }
        group.cancelAll()
        return result
    }
}
