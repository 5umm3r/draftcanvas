import Foundation

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
