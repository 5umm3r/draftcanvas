import Foundation

enum BuiltInPromptTemplates {
    static let all: [PromptTemplate] = [
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: String(localized: "水彩画"),
            prompt: "watercolor painting style, soft brush strokes, gentle color bleeding, textured paper",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: String(localized: "油絵"),
            prompt: "oil painting style, thick impasto brush strokes, rich saturated colors, canvas texture",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: String(localized: "フラットイラスト"),
            prompt: "flat vector illustration, clean lines, minimal shading, bold solid colors",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: String(localized: "写真風"),
            prompt: "photorealistic, natural lighting, shallow depth of field, high detail, 50mm lens",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: String(localized: "3Dレンダー"),
            prompt: "3D rendered, soft studio lighting, subsurface scattering, smooth materials, octane render",
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: String(localized: "ラインアート"),
            prompt: "clean line art, black and white, fine ink lines, no shading, minimalist",
            isBuiltIn: true
        ),
    ]
}
