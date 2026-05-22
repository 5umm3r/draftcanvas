import Foundation

// MARK: - Codex Model

struct CodexModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool
    let rating: ModelRating?
}

struct ModelRating: Equatable {
    let cost: String
    let smart: String
    let speed: String

    static let table: [String: ModelRating] = [
        "GPT-5.5":       .init(cost: "high", smart: "high", speed: "high"),
        "gpt-5.4":       .init(cost: "mid",  smart: "high", speed: "high"),
        "GPT-5.4-Mini":  .init(cost: "low",  smart: "mid",  speed: "high"),
        "gpt-5.3-codex": .init(cost: "low",  smart: "mid",  speed: "high"),
        "gpt-5.2":       .init(cost: "low",  smart: "low",  speed: "mid"),
    ]

    static func lookup(displayName: String) -> ModelRating? { table[displayName] }

    var costLevel: Int {
        switch cost.lowercased() {
        case "low":  return 1
        case "mid":  return 2
        case "high": return 3
        default:     return 0
        }
    }
}
