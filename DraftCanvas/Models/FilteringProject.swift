import Foundation

// MARK: - FilteringProject

struct FilteringProject: Identifiable, Equatable {
    let id: UUID
    var name: String
    var searchQuery: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        searchQuery: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.searchQuery = searchQuery
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension FilteringProject: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, searchQuery, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        searchQuery = try c.decodeIfPresent(String.self, forKey: .searchQuery) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
