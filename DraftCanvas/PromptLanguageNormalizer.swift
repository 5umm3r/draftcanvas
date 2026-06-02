import Foundation

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
