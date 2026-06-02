import Foundation

protocol GenerationRunning: AnyObject, Sendable {
    func run(
        job: GenerationJob,
        request: GenerationRequest
    ) async -> GenerationJob
}

actor ConcurrencyController {
    private let initial: Int
    private(set) var effective: Int
    private var consecutiveSuccess: Int = 0
    private let restoreThreshold = 5

    init(initial: Int) {
        self.initial = initial
        self.effective = initial
    }

    func didSucceed() -> (old: Int, new: Int)? {
        consecutiveSuccess += 1
        guard consecutiveSuccess >= restoreThreshold, effective < initial else { return nil }
        consecutiveSuccess = 0
        let old = effective
        effective = min(initial, effective + 1)
        return (old, effective)
    }

    func didHitRateLimit() -> (old: Int, new: Int)? {
        consecutiveSuccess = 0
        guard effective > 1 else { return nil }
        let old = effective
        effective = max(1, effective - 1)
        return (old, effective)
    }
}

final class GenerationCoordinator: @unchecked Sendable {
    private let runner: GenerationRunning
    var onConcurrencyAdjusted: (@Sendable (Int, Int) -> Void)?

    init(runner: GenerationRunning) {
        self.runner = runner
    }

    func run(
        request: GenerationRequest,
        onUpdate: (@Sendable (GenerationJob) async -> Void)? = nil
    ) async -> [GenerationJob] {
        let jobList = (0..<request.normalizedCount).map { index in
            GenerationJob(index: index, prompt: request.prompt, aspectRatio: request.aspectRatio)
        }
        return await runSpecific(jobs: jobList, request: request, onUpdate: onUpdate)
    }

    func runSpecific(
        jobs inputJobs: [GenerationJob],
        request: GenerationRequest,
        onUpdate: (@Sendable (GenerationJob) async -> Void)? = nil
    ) async -> [GenerationJob] {
        let controller = ConcurrencyController(initial: request.normalizedConcurrency)
        var jobs = inputJobs
        var positionByJobIndex: [Int: Int] = [:]
        for (pos, job) in jobs.enumerated() {
            positionByJobIndex[job.index] = pos
        }

        await withTaskGroup(of: GenerationJob.self) { group in
            var nextIndex = 0
            var running = 0

            func startNextJob(effectiveConcurrency: Int) {
                guard running < effectiveConcurrency, nextIndex < jobs.count else { return }
                var job = jobs[nextIndex]
                job.status = .running
                jobs[nextIndex] = job
                let capturedJob = job
                let runner = runner
                let request = request
                let onUpdate = onUpdate
                group.addTask {
                    await onUpdate?(capturedJob)
                    return await runner.run(job: capturedJob, request: request)
                }
                nextIndex += 1
                running += 1
            }

            var eff = await controller.effective
            while running < eff && nextIndex < jobs.count {
                startNextJob(effectiveConcurrency: eff)
            }

            while let completed = await group.next() {
                running -= 1
                if let pos = positionByJobIndex[completed.index] {
                    jobs[pos] = completed
                }
                await onUpdate?(completed)

                if completed.hitRateLimitDuringRun {
                    if let (old, new) = await controller.didHitRateLimit() {
                        onConcurrencyAdjusted?(old, new)
                    }
                } else if completed.status == .succeeded {
                    if let (old, new) = await controller.didSucceed() {
                        onConcurrencyAdjusted?(old, new)
                    }
                }

                eff = await controller.effective
                startNextJob(effectiveConcurrency: eff)
            }
        }

        return jobs
    }
}

final class CodexGenerationRunner: GenerationRunning {
    private let client: CodexAppServerClient

    init(client: CodexAppServerClient) {
        self.client = client
    }

    func run(
        job: GenerationJob,
        request: GenerationRequest
    ) async -> GenerationJob {
        var output = job
        output.logs.append("ジョブ \(job.index + 1) を開始しました。")

        do {
            let (result, extraLogs, hitRateLimit) = try await runWithRetry(
                job: job,
                request: request
            )
            output.hitRateLimitDuringRun = hitRateLimit
            output.logs.append(contentsOf: extraLogs)
            output.logs.append(contentsOf: result.logs)
            guard let imageResult = result.imageResult else {
                throw DraftCanvasError.missingGeneratedContent
            }
            output.imageData = imageResult.data
            output.revisedPrompt = imageResult.revisedPrompt
            output.status = .succeeded
            output.logs.append("ジョブ \(job.index + 1) が完了しました。")
        } catch {
            output.status = .failed
            if case DraftCanvasError.freePlanNotEntitled = error {
                output.isFreeAccountBlocked = true
            } else if case DraftCanvasError.rateLimited = error {
                output.failureKind = .rateLimited
            } else if case DraftCanvasError.timeout = error {
                output.failureKind = .timeout
            } else {
                output.failureKind = .other
            }
            output.errorMessage = error.localizedDescription
            output.logs.append("エラー: \(error.localizedDescription)")
        }

        return output
    }

    private func runWithRetry(
        job: GenerationJob,
        request: GenerationRequest,
        maxAttempts: Int = 3
    ) async throws -> (result: CodexTurnResult, logs: [String], hitRateLimit: Bool) {
        var extraLogs: [String] = []
        var lastError: Error = DraftCanvasError.missingGeneratedContent
        var hitRateLimit = false

        let referenceImagePath: String?
        if let editSource = request.editSource {
            referenceImagePath = editSource.compositeFilePath ?? editSource.filePath
        } else {
            referenceImagePath = request.attachedImagePath
        }
        let prompt = PromptFactory.prompt(for: request, jobIndex: job.index, jobPrompt: job.prompt)

        for attempt in 0..<maxAttempts {
            do {
                try await client.start()
                let threadID = try await client.startThread(
                    model: request.model,
                    reasoningEffort: request.reasoningEffort
                )
                extraLogs.append("Codex thread: \(threadID)")
                let result = try await client.runTurn(
                    threadID: threadID,
                    prompt: prompt,
                    referenceImagePath: referenceImagePath
                )
                return (result, extraLogs, hitRateLimit)
            } catch let error as DraftCanvasError {
                if case .rateLimited(let retryAfter) = error, attempt < maxAttempts - 1 {
                    hitRateLimit = true
                    let delay = retryAfter ?? (pow(2.0, Double(attempt)) * 2.0 + Double.random(in: 0..<1))
                    extraLogs.append("レート制限のため \(Int(delay.rounded())) 秒後に再試行します (\(attempt + 1)/\(maxAttempts - 1))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = error
                } else if case .threadIDCollision = error, attempt < maxAttempts - 1 {
                    extraLogs.append("thread ID 衝突のため再試行します (\(attempt + 1)/\(maxAttempts - 1))")
                    try await Task.sleep(nanoseconds: 500_000_000)
                    lastError = error
                } else {
                    throw error
                }
            }
        }
        throw lastError
    }
}
