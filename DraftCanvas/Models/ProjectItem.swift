import Foundation
import CoreGraphics

struct ProjectItem: Identifiable, Equatable {
    let id: UUID
    var projectID: UUID
    let prompt: String
    let revisedPrompt: String?
    let aspectRatio: GenerationAspectRatio
    let actualAspectRatio: CGFloat?
    let createdAt: Date
    let errorMessage: String?
    var editedFromItemID: UUID?
    let hasSVG: Bool
    let isBackgroundRemoved: Bool
    let isCropped: Bool
    let isImported: Bool
    var tags: [String]
    var sketchSourcePath: String?
    let modelName: String?
    let reasoningEffort: String?
    let generationDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        prompt: String,
        revisedPrompt: String? = nil,
        aspectRatio: GenerationAspectRatio,
        actualAspectRatio: CGFloat? = nil,
        createdAt: Date = Date(),
        errorMessage: String? = nil,
        editedFromItemID: UUID? = nil,
        hasSVG: Bool = false,
        isBackgroundRemoved: Bool = false,
        isCropped: Bool = false,
        isImported: Bool = false,
        tags: [String] = [],
        sketchSourcePath: String? = nil,
        modelName: String? = nil,
        reasoningEffort: String? = nil,
        generationDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.prompt = prompt
        self.revisedPrompt = revisedPrompt
        self.aspectRatio = aspectRatio
        self.actualAspectRatio = actualAspectRatio
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.editedFromItemID = editedFromItemID
        self.hasSVG = hasSVG
        self.isBackgroundRemoved = isBackgroundRemoved
        self.isCropped = isCropped
        self.isImported = isImported
        self.tags = tags
        self.sketchSourcePath = sketchSourcePath
        self.modelName = modelName
        self.reasoningEffort = reasoningEffort
        self.generationDuration = generationDuration
    }

    func fileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).png")
    }

    func svgFileURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).svg")
    }
}

extension ProjectItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, projectID, prompt, revisedPrompt, aspectRatio, actualAspectRatio, createdAt, errorMessage, editedFromItemID
        case hasSVG
        case isBackgroundRemoved
        case isCropped
        case isImported
        case tags
        case sketchSourcePath
        case modelName
        case reasoningEffort
        case generationDuration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        prompt = try c.decode(String.self, forKey: .prompt)
        revisedPrompt = try c.decodeIfPresent(String.self, forKey: .revisedPrompt)
        aspectRatio = try c.decodeIfPresent(GenerationAspectRatio.self, forKey: .aspectRatio) ?? .square
        actualAspectRatio = try c.decodeIfPresent(CGFloat.self, forKey: .actualAspectRatio)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        editedFromItemID = try c.decodeIfPresent(UUID.self, forKey: .editedFromItemID)
        hasSVG = try c.decodeIfPresent(Bool.self, forKey: .hasSVG) ?? false
        isBackgroundRemoved = try c.decodeIfPresent(Bool.self, forKey: .isBackgroundRemoved) ?? false
        isCropped = try c.decodeIfPresent(Bool.self, forKey: .isCropped) ?? false
        isImported = try c.decodeIfPresent(Bool.self, forKey: .isImported) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        sketchSourcePath = try c.decodeIfPresent(String.self, forKey: .sketchSourcePath)
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        generationDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .generationDuration)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(prompt, forKey: .prompt)
        try c.encodeIfPresent(revisedPrompt, forKey: .revisedPrompt)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(actualAspectRatio, forKey: .actualAspectRatio)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(editedFromItemID, forKey: .editedFromItemID)
        if hasSVG { try c.encode(hasSVG, forKey: .hasSVG) }
        if isBackgroundRemoved { try c.encode(isBackgroundRemoved, forKey: .isBackgroundRemoved) }
        if isCropped { try c.encode(isCropped, forKey: .isCropped) }
        if isImported { try c.encode(isImported, forKey: .isImported) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encodeIfPresent(sketchSourcePath, forKey: .sketchSourcePath)
        try c.encodeIfPresent(modelName, forKey: .modelName)
        try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try c.encodeIfPresent(generationDuration, forKey: .generationDuration)
    }
}
