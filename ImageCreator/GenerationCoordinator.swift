import Foundation

protocol GenerationRunning: AnyObject {
    func run(job: GenerationJob, request: GenerationRequest) async -> GenerationJob
}

final class GenerationCoordinator {
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
            GenerationJob(index: index, prompt: request.prompt)
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
            let threadID = try await client.startThread()
            output.logs.append("Codex thread: \(threadID)")

            let prompt = PromptFactory.prompt(for: request, jobIndex: job.index)
            let result = try await client.runTurn(
                threadID: threadID,
                prompt: prompt,
                outputMode: request.outputMode
            )

            output.logs.append(contentsOf: result.logs)
            switch request.outputMode {
            case .raster:
                guard let imageResult = result.imageResult else {
                    throw ImageCreatorError.missingGeneratedContent
                }
                output.imageData = imageResult.data
                output.revisedPrompt = imageResult.revisedPrompt
                if request.transparentBackground {
                    switch PNGInspector.hasAlphaChannel(imageResult.data) {
                    case .some(true):
                        output.logs.append("PNGのアルファチャンネルを確認しました。")
                    case .some(false):
                        output.logs.append("透過指定ありですが、PNGのアルファチャンネルは確認できませんでした。")
                    case .none:
                        output.logs.append("PNG透過情報を判定できませんでした。")
                    }
                }
            case .svg:
                guard let svgText = result.svgText ?? SVGExtractor.extract(from: result.assistantText) else {
                    throw ImageCreatorError.svgExtractionFailed
                }
                output.svgText = svgText
            }

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
        switch request.outputMode {
        case .raster:
            return rasterPrompt(for: request, jobIndex: jobIndex)
        case .svg:
            return svgPrompt(for: request, jobIndex: jobIndex)
        }
    }

    private static func rasterPrompt(for request: GenerationRequest, jobIndex: Int) -> String {
        var lines = [
            "Generate exactly one high-quality raster image for a local personal image creator app.",
            "Use the image generation capability and return the generated image result.",
            "User prompt: \(request.prompt)",
            "Variation number: \(jobIndex + 1).",
            "Do not write code. Do not ask clarifying questions."
        ]

        if request.transparentBackground {
            lines.append("The image must be a PNG with a transparent background and alpha channel.")
        } else {
            lines.append("A normal opaque image is acceptable.")
        }

        return lines.joined(separator: "\n")
    }

    private static func svgPrompt(for request: GenerationRequest, jobIndex: Int) -> String {
        [
            "Create exactly one complete SVG image.",
            "Return only the SVG XML, starting with <svg and ending with </svg>.",
            "Do not wrap it in Markdown fences.",
            "Use clean vector shapes suitable for saving directly as an .svg file.",
            "User prompt: \(request.prompt)",
            "Variation number: \(jobIndex + 1).",
            request.transparentBackground ? "Use a transparent SVG background." : "Use an SVG composition that can render on a light canvas."
        ].joined(separator: "\n")
    }
}
