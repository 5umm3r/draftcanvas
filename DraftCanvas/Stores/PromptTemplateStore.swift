import Foundation

final class PromptTemplateStore {
    private let fileURL: URL

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.fileURL = rootDirectory.appendingPathComponent("prompt_templates.json")
    }

    func load() -> [PromptTemplate] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PromptTemplate].self, from: data)) ?? []
    }

    func save(_ templates: [PromptTemplate]) {
        let userTemplates = templates.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(userTemplates) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
