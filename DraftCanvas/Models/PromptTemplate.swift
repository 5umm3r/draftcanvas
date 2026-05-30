import Foundation

struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var promptText: String
    let isBuiltIn: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, promptText: String, isBuiltIn: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.promptText = promptText
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}

extension PromptTemplate {
    static let builtIns: [PromptTemplate] = [
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            name: String(localized: "水彩画風"),
            promptText: "watercolor painting style, soft watercolor washes, translucent layers, paper texture visible, delicate brushwork, bleeding ink edges",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000002")!,
            name: String(localized: "油絵風"),
            promptText: "oil painting style, thick impasto brushstrokes, rich saturated colors, visible canvas texture, dramatic chiaroscuro lighting",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000003")!,
            name: String(localized: "フラットイラスト"),
            promptText: "flat design illustration, clean vector-like style, bold solid colors, minimal shading, simple geometric shapes",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000004")!,
            name: String(localized: "写真風"),
            promptText: "photorealistic photography, shot on 85mm lens, natural soft lighting, shallow depth of field, high resolution detail",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000005")!,
            name: String(localized: "3Dレンダー風"),
            promptText: "3D rendered image, ray-traced lighting, subsurface scattering, ambient occlusion, physically-based rendering, cinema quality",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000006")!,
            name: String(localized: "ラインアート"),
            promptText: "clean line art, precise ink drawing, bold outlines, minimal hatching, black and white with selective color accents",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000007")!,
            name: String(localized: "ピクセルアート"),
            promptText: "pixel art style, 32x32 sprite aesthetic, limited 16-color palette, crisp hard edges, no anti-aliasing, retro video game",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000008")!,
            name: String(localized: "鉛筆スケッチ"),
            promptText: "pencil sketch drawing, graphite texture, rough construction lines, cross-hatching shading, artistic study, sketchbook paper",
            isBuiltIn: true
        ),
    ]
}
