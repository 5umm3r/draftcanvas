import Foundation

// MARK: - Codex types

struct CodexImageResult: Equatable {
    let imageID: String
    let data: Data
    let revisedPrompt: String?
}

struct CodexTurnResult: Equatable {
    var imageResult: CodexImageResult?
    var assistantText: String
    var logs: [String]
}
