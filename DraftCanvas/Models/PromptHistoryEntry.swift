import Foundation

struct PromptHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var prompt: String
    var lastUsedAt: Date
    var useCount: Int

    init(id: UUID = UUID(), prompt: String, lastUsedAt: Date = Date(), useCount: Int = 1) {
        self.id = id
        self.prompt = prompt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}
