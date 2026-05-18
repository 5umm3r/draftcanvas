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

        await withTaskGroup(of: GenerationJob.self) { group in
            var nextIndex = 0
            var running = 0

            func startNextJob(effectiveConcurrency: Int) {
                guard running < effectiveConcurrency, nextIndex < jobs.count else { return }
                var job = jobs[nextIndex]
                job.status = .running
                jobs[job.index] = job
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
                jobs[completed.index] = completed
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
        let prompt = PromptFactory.prompt(for: request, jobIndex: job.index)

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

enum PromptFactory {
    static func prompt(for request: GenerationRequest, jobIndex: Int) -> String {
        if let editSource = request.editSource {
            let userInstructionLines: [String]
            if let normalizedBrief = request.normalizedGenerationBrief {
                userInstructionLines = ["Generation brief: \(normalizedBrief)"]
            } else {
                userInstructionLines = [
                    "Original prompt: \(editSource.originalPrompt)",
                    "User edit request: \(request.prompt)"
                ]
            }

            if editSource.isInpainting && editSource.inpaintPurpose == .remove {
                return [
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be removed.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Remove the object in the transparent area, naturally fill with surrounding background.",
                    request.normalizedGenerationBrief.map { "Generation brief: \($0)" }
                        ?? "Original image description: \(editSource.originalPrompt)",
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ].joined(separator: "\n")
            }
            if editSource.isInpainting {
                return ([
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be regenerated.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Fill in the transparent regions according to the following user instruction:",
                ] + userInstructionLines + [
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Only modify the transparent regions to match the user edit request.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ]).joined(separator: "\n")
            }
            return ([
                "Edit the attached reference image for a local personal image creator app.",
                "Use the image generation capability and return exactly one edited raster image result.",
            ] + userInstructionLines + [
                "Aspect ratio: \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "Preserve useful parts of the reference image unless the edit request says otherwise.",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions."
            ]).joined(separator: "\n")
        }

        let promptLine = request.normalizedGenerationBrief.map { "Generation brief: \($0)" }
            ?? "User prompt: \(request.prompt)"

        if request.attachedImagePath != nil {
            return [
                "Generate exactly one high-quality raster image for a local personal image creator app.",
                "Use the attached reference image as visual guidance.",
                "Use the image generation capability and return the generated image result.",
                promptLine,
                "Aspect ratio: \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions."
            ].joined(separator: "\n")
        }

        return [
            "Generate exactly one high-quality raster image for a local personal image creator app.",
            "Use the image generation capability and return the generated image result.",
            promptLine,
            "Aspect ratio: \(request.aspectRatio.promptDescription).",
            "Variation number: \(jobIndex + 1).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions."
        ].joined(separator: "\n")
    }

    static func upscalePrompt(
        for item: ProjectItem,
        translateToEnglish: Bool = false,
        normalizedDescription: String? = nil
    ) -> String {
        let fallbackDescription = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "imported asset"
            : item.prompt
        let normalized = normalizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = translateToEnglish && normalized?.isEmpty == false
            ? normalized!
            : fallbackDescription
        let descriptionLabel = translateToEnglish && normalized?.isEmpty == false
            ? "Image brief"
            : "Original image description"
        return [
            "Upscale the attached reference image to a significantly higher resolution.",
            "Preserve the original composition, subject, style, and color palette exactly.",
            "Enhance fine details: textures, edges, fine lines, small features.",
            "Do not add, remove, or alter any objects.",
            "\(descriptionLabel): \(description)",
            "Aspect ratio: \(item.aspectRatio.promptDescription).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions."
        ].joined(separator: "\n")
    }
}

enum PromptEnhancer {
    static let systemInstruction: String = systemInstruction(translateToEnglish: false)

    static func systemInstruction(translateToEnglish: Bool) -> String {
        let languageRule = translateToEnglish
            ? "- Output the enhanced prompt in English"
            : "- Maintain the same language as the input (Japanese stays Japanese, English stays English)"

        return [
        "You are an expert prompt engineer for AI image generation.",
        "Enhance the user's prompt to produce higher quality image results.",
        "",
        "Rules:",
        languageRule,
        "- Add vivid details: composition, color palette, lighting, atmosphere, texture, perspective, artistic style",
        "- Keep the original intent and subject matter intact",
        "- Output ONLY the enhanced prompt text, nothing else",
        "- No explanations, labels, prefixes, markdown formatting, or surrounding quotes",
        "- Aim for 2-4 sentences",
        "- Do not generate any images",
        "- Do not write any code",
        ].joined(separator: "\n")
    }

    static func buildPrompt(userPrompt: String, translateToEnglish: Bool = false) -> String {
        [systemInstruction(translateToEnglish: translateToEnglish), "", "User's prompt:", userPrompt].joined(separator: "\n")
    }
}

enum PromptLanguageNormalizer {
    static func buildPrompt(for request: GenerationRequest) -> String {
        var context = [
            "User prompt: \(request.prompt)",
            "Aspect ratio: \(request.aspectRatio.promptDescription)"
        ]

        if let editSource = request.editSource {
            context.insert("Request type: image edit", at: 0)
            context.append("Original image description: \(editSource.originalPrompt)")
            if editSource.isInpainting {
                context.append("Inpainting: transparent regions are the only edit target")
            }
            if editSource.inpaintPurpose == .remove {
                context.append("Edit purpose: remove masked object and fill the background naturally")
            }
        } else if request.attachedImagePath != nil {
            context.insert("Request type: generation with reference image", at: 0)
        } else {
            context.insert("Request type: text-to-image generation", at: 0)
        }

        return [
            "You are preparing a stable English brief for AI image generation.",
            "Rewrite the request below into clear English for an image generation model.",
            "Keep the user's visual intent, subject, composition, style, colors, and constraints intact.",
            "Do not add new subject matter that the user did not request.",
            "Output ONLY the English image-generation brief, with no labels, markdown, quotes, or explanations.",
            "",
            "Request:",
            context.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    static func buildPromptForUpscale(description: String) -> String {
        [
            "You are preparing a stable English brief for AI image upscaling.",
            "Rewrite the image description below into concise English.",
            "Preserve the original subject, composition, style, and color palette.",
            "Output ONLY the English image description, with no labels, markdown, quotes, or explanations.",
            "",
            "Image description:",
            description
        ].joined(separator: "\n")
    }

    static func sanitize(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while output.hasPrefix("\"") || output.hasPrefix("'") || output.hasPrefix("`") {
            output = String(output.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while output.hasSuffix("\"") || output.hasSuffix("'") || output.hasSuffix("`") {
            output = String(output.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
    }

    static func normalize(
        request: GenerationRequest,
        client: CodexAppServerClient,
        model: CodexModel
    ) async throws -> String {
        try await client.start()
        let threadID = try await client.startThread(model: model.id, reasoningEffort: "low")
        let result = try await client.runTurn(threadID: threadID, prompt: buildPrompt(for: request))
        return sanitize(result.assistantText)
    }

    static func normalizeUpscaleDescription(
        _ description: String,
        client: CodexAppServerClient,
        model: CodexModel
    ) async throws -> String {
        try await client.start()
        let threadID = try await client.startThread(model: model.id, reasoningEffort: "low")
        let result = try await client.runTurn(threadID: threadID, prompt: buildPromptForUpscale(description: description))
        return sanitize(result.assistantText)
    }
}
