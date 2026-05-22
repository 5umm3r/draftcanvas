import Foundation

// MARK: - ProjectNaming

enum ProjectNaming {
    static let maxCharacters = 20

    static func summarize(_ prompt: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !normalized.isEmpty else { return defaultName() }
        if normalized.count <= maxCharacters { return normalized }
        return String(normalized.prefix(maxCharacters)) + "…"
    }

    static func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return String(localized: "新規プロジェクト ") + f.string(from: Date())
    }
}
