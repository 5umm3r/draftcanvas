import Foundation

struct ChangelogSection: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let categories: [ChangelogCategory]
}

struct ChangelogCategory: Identifiable {
    let id = UUID()
    let name: String
    let items: [String]
}

enum ReleaseNotesLoader {
    enum LoadError: LocalizedError {
        case notFound

        var errorDescription: String? { "CHANGELOG.md がバンドルに見つかりません" }
    }

    static func load() throws -> [ChangelogSection] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
            throw LoadError.notFound
        }
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return parse(raw)
    }

    private static func parse(_ text: String) -> [ChangelogSection] {
        var sections: [ChangelogSection] = []
        var currentVersion = ""
        var currentDate = ""
        var currentCategories: [ChangelogCategory] = []
        var currentCategoryName = ""
        var currentItems: [String] = []

        func flushCategory() {
            guard !currentCategoryName.isEmpty else { return }
            currentCategories.append(ChangelogCategory(name: currentCategoryName, items: currentItems))
            currentCategoryName = ""
            currentItems = []
        }

        func flushSection() {
            guard !currentVersion.isEmpty else { return }
            flushCategory()
            sections.append(ChangelogSection(version: currentVersion, date: currentDate, categories: currentCategories))
            currentVersion = ""
            currentDate = ""
            currentCategories = []
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flushSection()
                let rest = String(line.dropFirst(3))
                // "## [1.0.4] - 2026-05-27" or "## [Unreleased]"
                let parts = rest.components(separatedBy: " - ")
                currentVersion = parts.first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) } ?? rest
                currentDate = parts.count > 1 ? parts[1] : ""
            } else if line.hasPrefix("### ") {
                flushCategory()
                currentCategoryName = String(line.dropFirst(4))
            } else if line.hasPrefix("- ") {
                currentItems.append(String(line.dropFirst(2)))
            }
        }
        flushSection()
        return sections
    }
}
