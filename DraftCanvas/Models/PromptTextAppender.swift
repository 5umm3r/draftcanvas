import Foundation

enum PromptTextAppender {
    static func smartAppend(existing: String, addition: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return addition }

        var base = trimmed
        while base.hasSuffix(" ") { base = String(base.dropLast()) }
        if base.hasSuffix(",") { base = String(base.dropLast()) }

        return base + ", " + addition
    }
}
