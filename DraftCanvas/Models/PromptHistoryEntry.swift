import Foundation

struct PromptHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var promptText: String
    var useCount: Int
    var lastUsedAt: Date

    init(promptText: String) {
        self.id = UUID()
        self.promptText = promptText
        self.useCount = 1
        self.lastUsedAt = Date()
    }
}
