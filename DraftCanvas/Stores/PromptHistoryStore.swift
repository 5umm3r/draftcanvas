import Foundation

final class PromptHistoryStore: JSONFileStore {
    typealias Payload = [PromptHistoryEntry]

    private static let maxEntries = 50

    var fileURL: URL {
        ProjectStore.defaultRootDirectory()
            .appendingPathComponent("prompt_history.json")
    }

    private var entries: [PromptHistoryEntry]

    init() {
        self.entries = [] // 後で load() で読み込む
    }

    func loadEntries() -> [PromptHistoryEntry] {
        entries = load() ?? []
        return entries
    }

    func record(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lowered = trimmed.lowercased()
        if let idx = entries.firstIndex(where: { $0.prompt.lowercased() == lowered }) {
            // 重複: useCount 加算、先頭へ移動
            var entry = entries.remove(at: idx)
            entry.useCount += 1
            entry.lastUsedAt = Date()
            entries.insert(entry, at: 0)
        } else {
            entries.insert(PromptHistoryEntry(prompt: trimmed), at: 0)
        }

        // 上限50件
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        save(entries)
    }

    func allEntries() -> [PromptHistoryEntry] {
        entries
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func clear() {
        entries = []
        save(entries)
    }
}
