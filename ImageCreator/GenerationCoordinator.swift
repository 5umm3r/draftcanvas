import Foundation

protocol GenerationRunning: AnyObject, Sendable {
    func run(job: GenerationJob, request: GenerationRequest) async -> GenerationJob
}

final class GenerationCoordinator: Sendable {
    private let runner: GenerationRunning

    init(runner: GenerationRunning) {
        self.runner = runner
    }

    func run(
        request: GenerationRequest,
        onUpdate: (@Sendable (GenerationJob) async -> Void)? = nil
    ) async -> [GenerationJob] {
        let count = request.normalizedCount
        let concurrency = request.normalizedConcurrency
        var jobs = (0..<count).map { index in
            GenerationJob(index: index, prompt: request.prompt, aspectRatio: request.aspectRatio)
        }

        await withTaskGroup(of: GenerationJob.self) { group in
            var nextIndex = 0
            var running = 0

            func startNextJob() {
                guard nextIndex < jobs.count else { return }

                var job = jobs[nextIndex]
                job.status = .running
                jobs[job.index] = job
                let runner = runner
                let request = request
                group.addTask {
                    await onUpdate?(job)
                    return await runner.run(job: job, request: request)
                }

                nextIndex += 1
                running += 1
            }

            while running < concurrency && nextIndex < jobs.count {
                startNextJob()
            }

            while let completed = await group.next() {
                running -= 1
                jobs[completed.index] = completed
                await onUpdate?(completed)
                startNextJob()
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

    func run(job: GenerationJob, request: GenerationRequest) async -> GenerationJob {
        var output = job
        output.logs.append("ジョブ \(job.index + 1) を開始しました。")

        do {
            try await client.start()
            let threadID = try await client.startThread(model: request.model, reasoningEffort: request.reasoningEffort)
            output.logs.append("Codex thread: \(threadID)")

            let prompt = PromptFactory.prompt(for: request, jobIndex: job.index)
            let referenceImagePath = request.editSource.map { src in
                src.compositeFilePath ?? src.filePath
            }
            let result = try await client.runTurn(
                threadID: threadID,
                prompt: prompt,
                referenceImagePath: referenceImagePath
            )

            output.logs.append(contentsOf: result.logs)
            guard let imageResult = result.imageResult else {
                throw ImageCreatorError.missingGeneratedContent
            }
            output.imageData = imageResult.data
            output.revisedPrompt = imageResult.revisedPrompt

            output.status = .succeeded
            output.logs.append("ジョブ \(job.index + 1) が完了しました。")
        } catch {
            output.status = .failed
            output.errorMessage = error.localizedDescription
            output.logs.append("エラー: \(error.localizedDescription)")
        }

        return output
    }
}

enum PromptFactory {
    static func prompt(for request: GenerationRequest, jobIndex: Int) -> String {
        if let editSource = request.editSource {
            if editSource.isInpainting {
                return [
                    "Edit the attached reference image for a local personal image creator app.",
                    "The reference image has transparent (alpha=0) regions indicating areas to be regenerated.",
                    "Use the image generation capability and return exactly one edited raster image result.",
                    "Fill in the transparent regions according to the following user instruction:",
                    "User edit request: \(request.prompt)",
                    "Original image description: \(editSource.originalPrompt)",
                    "Aspect ratio: \(request.aspectRatio.promptDescription).",
                    "Variation number: \(jobIndex + 1).",
                    "Preserve all non-transparent parts of the image exactly as they are.",
                    "Only modify the transparent regions to match the user edit request.",
                    "Return a fully opaque image with no transparency.",
                    "Do not write code. Do not ask clarifying questions."
                ].joined(separator: "\n")
            }
            return [
                "Edit the attached reference image for a local personal image creator app.",
                "Use the image generation capability and return exactly one edited raster image result.",
                "Original prompt: \(editSource.originalPrompt)",
                "User edit request: \(request.prompt)",
                "Aspect ratio: \(request.aspectRatio.promptDescription).",
                "Variation number: \(jobIndex + 1).",
                "Preserve useful parts of the reference image unless the edit request says otherwise.",
                "A normal opaque image is acceptable.",
                "Do not write code. Do not ask clarifying questions."
            ].joined(separator: "\n")
        }

        return [
            "Generate exactly one high-quality raster image for a local personal image creator app.",
            "Use the image generation capability and return the generated image result.",
            "User prompt: \(request.prompt)",
            "Aspect ratio: \(request.aspectRatio.promptDescription).",
            "Variation number: \(jobIndex + 1).",
            "A normal opaque image is acceptable.",
            "Do not write code. Do not ask clarifying questions."
        ].joined(separator: "\n")
    }
}
