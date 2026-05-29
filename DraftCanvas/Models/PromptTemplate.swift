import Foundation

struct PromptTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var isBuiltIn: Bool
    // 任意の生成設定
    var count: Int?
    var aspectRatio: GenerationAspectRatio?
    var model: String?
    var reasoningEffort: String?

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        isBuiltIn: Bool = false,
        count: Int? = nil,
        aspectRatio: GenerationAspectRatio? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isBuiltIn = isBuiltIn
        self.count = count
        self.aspectRatio = aspectRatio
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    // 後方互換デコード（任意フィールドが欠けてもデコード可能）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        aspectRatio = try c.decodeIfPresent(GenerationAspectRatio.self, forKey: .aspectRatio)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
    }
}
