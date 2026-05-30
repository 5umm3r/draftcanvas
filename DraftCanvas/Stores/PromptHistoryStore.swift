import Foundation

final class PromptHistoryStore {
    private let fileURL: URL

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.fileURL = rootDirectory.appendingPathComponent("prompt_history.json")
    }

    func load() -> [PromptHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PromptHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [PromptHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
