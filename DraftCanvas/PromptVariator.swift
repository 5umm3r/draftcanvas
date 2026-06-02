import Foundation

enum PromptVariator {
    static func systemInstruction(count: Int, translateToEnglish: Bool) -> String {
        let languageRule = translateToEnglish
            ? "- Write every variation in English"
            : "- Write each variation in the same language as the original prompt (Japanese stays Japanese, English stays English)"

        return [
            "You are an expert prompt engineer for AI image generation.",
            "Given an original image prompt, produce \(count) distinct variations of it.",
            "",
            "Rules:",
            "- Keep the same core subject and intent as the original prompt",
            "- Each variation must explore a DIFFERENT visual axis: composition, camera angle, lighting, color palette, mood, art style, season, or time of day",
            "- Do not repeat the same axis across variations; make them clearly distinct from one another",
            languageRule,
            "- Each variation must be a complete, self-contained image prompt (2-4 sentences)",
            "- Output ONLY a JSON array of exactly \(count) strings, nothing else",
            "- No markdown, no code fences, no labels, no explanations",
            "- Do not generate any images",
            "- Do not write any code",
        ].joined(separator: "\n")
    }

    static func buildPrompt(originalPrompt: String, count: Int, translateToEnglish: Bool) -> String {
        [
            systemInstruction(count: count, translateToEnglish: translateToEnglish),
            "",
            "Original prompt:",
            originalPrompt
        ].joined(separator: "\n")
    }

    static func parseVariations(_ text: String) -> [String] {
        let sanitized = stripCodeFence(text)
        guard let data = sanitized.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripCodeFence(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("```") {
            if let firstNewline = output.firstIndex(of: "\n") {
                output = String(output[output.index(after: firstNewline)...])
            }
            if output.hasSuffix("```") {
                output = String(output.dropLast(3))
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func generate(
        originalPrompt: String,
        count: Int,
        translateToEnglish: Bool,
        client: CodexAppServerClient,
        model: CodexModel
    ) async throws -> [String] {
        try await client.start()
        let threadID = try await client.startThread(model: model.id, reasoningEffort: "low")
        let result = try await client.runTurn(
            threadID: threadID,
            prompt: buildPrompt(originalPrompt: originalPrompt, count: count, translateToEnglish: translateToEnglish)
        )
        return parseVariations(result.assistantText)
    }
}
