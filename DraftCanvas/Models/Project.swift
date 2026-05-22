import Foundation

// MARK: - Project

struct Project: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isAutoNamed: Bool
    let createdAt: Date
    var updatedAt: Date
    var model: String
    var reasoningEffort: String
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isAutoNamed: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        model: String = "",
        reasoningEffort: String = "medium",
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isAutoNamed = isAutoNamed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.isFavorite = isFavorite
    }
}

extension Project: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, isAutoNamed, createdAt, updatedAt, model, reasoningEffort, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isAutoNamed = try c.decode(Bool.self, forKey: .isAutoNamed)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? "medium"
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}
