import Foundation

enum PromptTemplateCategory: String, Codable, CaseIterable, Identifiable {
    case style    = "style"
    case photo    = "photo"
    case lighting = "lighting"
    case user     = "user"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .style:    return String(localized: "画風・スタイル")
        case .photo:    return String(localized: "写真・カメラ")
        case .lighting: return String(localized: "ライティング・雰囲気")
        case .user:     return String(localized: "マイテンプレート")
        }
    }

    var systemImage: String {
        switch self {
        case .style:    return "paintpalette"
        case .photo:    return "camera"
        case .lighting: return "light.max"
        case .user:     return "person.crop.circle"
        }
    }
}

struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var promptText: String
    let isBuiltIn: Bool
    var createdAt: Date
    var category: PromptTemplateCategory
    var thumbnailImageName: String?

    init(id: UUID = UUID(), name: String, promptText: String, isBuiltIn: Bool = false, createdAt: Date = Date(), category: PromptTemplateCategory = .user, thumbnailImageName: String? = nil) {
        self.id = id
        self.name = name
        self.promptText = promptText
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.category = category
        self.thumbnailImageName = thumbnailImageName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        promptText = try container.decode(String.self, forKey: .promptText)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        category = try container.decodeIfPresent(PromptTemplateCategory.self, forKey: .category) ?? .user
        thumbnailImageName = try container.decodeIfPresent(String.self, forKey: .thumbnailImageName)
    }
}

// MARK: - Built-in Presets

extension PromptTemplate {
    private static func builtIn(uuid: String, name: String, promptText: String, category: PromptTemplateCategory, thumbnailImageName: String? = nil) -> PromptTemplate {
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-\(uuid)")!,
            name: name,
            promptText: promptText,
            isBuiltIn: true,
            category: category,
            thumbnailImageName: thumbnailImageName
        )
    }

    static let builtIns: [PromptTemplate] = stylePresets + photoPresets + lightingPresets

    // MARK: 画風・スタイル

    private static let stylePresets: [PromptTemplate] = [
        builtIn(uuid: "000000000001", name: String(localized: "水彩画風"),
                promptText: "watercolor painting style, soft watercolor washes, translucent layers, paper texture visible, delicate brushwork, bleeding ink edges",
                category: .style, thumbnailImageName: "template-style-01"),
        builtIn(uuid: "000000000002", name: String(localized: "油絵風"),
                promptText: "oil painting style, thick impasto brushstrokes, rich saturated colors, visible canvas texture, dramatic chiaroscuro lighting",
                category: .style, thumbnailImageName: "template-style-02"),
        builtIn(uuid: "000000000003", name: String(localized: "フラットイラスト"),
                promptText: "flat design illustration, clean vector-like style, bold solid colors, minimal shading, simple geometric shapes",
                category: .style, thumbnailImageName: "template-style-03"),
        builtIn(uuid: "000000000004", name: String(localized: "ピクセルアート"),
                promptText: "pixel art style, 32x32 sprite aesthetic, limited 16-color palette, crisp hard edges, no anti-aliasing, retro video game",
                category: .style, thumbnailImageName: "template-style-04"),
        builtIn(uuid: "000000000005", name: String(localized: "ラインアート"),
                promptText: "clean line art, precise ink drawing, bold outlines, minimal hatching, black and white with selective color accents",
                category: .style, thumbnailImageName: "template-style-05"),
        builtIn(uuid: "000000000006", name: String(localized: "鉛筆スケッチ"),
                promptText: "pencil sketch drawing, graphite texture, rough construction lines, cross-hatching shading, artistic study, sketchbook paper",
                category: .style, thumbnailImageName: "template-style-06"),
        builtIn(uuid: "000000000007", name: String(localized: "アニメ風"),
                promptText: "anime illustration style, cel-shaded coloring, large expressive eyes, clean outlines, vibrant color palette, manga-inspired composition",
                category: .style, thumbnailImageName: "template-style-07"),
        builtIn(uuid: "000000000008", name: String(localized: "浮世絵風"),
                promptText: "ukiyo-e woodblock print style, flat color areas, bold black outlines, traditional Japanese composition, wave patterns, washi paper texture",
                category: .style, thumbnailImageName: "template-style-08"),
        builtIn(uuid: "000000000009", name: String(localized: "ローポリ3D"),
                promptText: "low-poly 3D render, geometric faceted surfaces, minimal polygon count, flat shading, pastel color palette, abstract simplified forms",
                category: .style, thumbnailImageName: "template-style-09"),
        builtIn(uuid: "00000000000a", name: String(localized: "コミック風"),
                promptText: "comic book illustration, bold ink outlines, halftone dot shading, dynamic action poses, speech bubble layout, vivid primary colors",
                category: .style, thumbnailImageName: "template-style-10"),
    ]

    // MARK: 写真・カメラ

    private static let photoPresets: [PromptTemplate] = [
        builtIn(uuid: "000000000010", name: String(localized: "写真風"),
                promptText: "photorealistic photography, shot on 85mm lens, natural soft lighting, shallow depth of field, high resolution detail",
                category: .photo, thumbnailImageName: "template-photo-01"),
        builtIn(uuid: "000000000011", name: String(localized: "ポートレート"),
                promptText: "portrait photography, 50mm f/1.4 lens, soft bokeh background, studio lighting, catchlight in eyes, skin detail preserved",
                category: .photo, thumbnailImageName: "template-photo-02"),
        builtIn(uuid: "000000000012", name: String(localized: "マクロ撮影"),
                promptText: "macro photography, extreme close-up, razor-thin depth of field, intricate surface details, ring light illumination, 1:1 magnification",
                category: .photo, thumbnailImageName: "template-photo-03"),
        builtIn(uuid: "000000000013", name: String(localized: "俯瞰"),
                promptText: "bird's-eye view, top-down perspective, aerial photography, flat lay composition, overhead angle, symmetrical arrangement",
                category: .photo, thumbnailImageName: "template-photo-04"),
        builtIn(uuid: "000000000014", name: String(localized: "魚眼レンズ"),
                promptText: "fisheye lens effect, ultra-wide 8mm focal length, barrel distortion, 180-degree field of view, spherical perspective warp",
                category: .photo, thumbnailImageName: "template-photo-05"),
        builtIn(uuid: "000000000015", name: String(localized: "ボケ"),
                promptText: "beautiful bokeh, f/1.2 wide aperture, soft circular highlights, creamy out-of-focus areas, dreamy background blur, light orbs",
                category: .photo, thumbnailImageName: "template-photo-06"),
        builtIn(uuid: "000000000016", name: String(localized: "ゴールデンアワー"),
                promptText: "golden hour photography, warm amber sunlight, long soft shadows, lens flare, backlit subject, magical warm tone",
                category: .photo, thumbnailImageName: "template-photo-07"),
        builtIn(uuid: "000000000017", name: String(localized: "長時間露光"),
                promptText: "long exposure photography, motion blur trails, silky smooth water, light painting streaks, 30-second shutter, tripod-steady composition",
                category: .photo, thumbnailImageName: "template-photo-08"),
        builtIn(uuid: "000000000018", name: String(localized: "フィルムグレイン"),
                promptText: "analog film grain, Kodak Portra 400 color profile, slight color shift, organic noise texture, vintage analog feel, light leaks",
                category: .photo, thumbnailImageName: "template-photo-09"),
        builtIn(uuid: "000000000019", name: String(localized: "ティルトシフト"),
                promptText: "tilt-shift photography, miniature effect, selective focus band, toy-like appearance, saturated colors, diorama perspective",
                category: .photo, thumbnailImageName: "template-photo-10"),
    ]

    // MARK: ライティング・雰囲気

    private static let lightingPresets: [PromptTemplate] = [
        builtIn(uuid: "000000000020", name: String(localized: "シネマティック"),
                promptText: "cinematic lighting, anamorphic lens flare, film color grading, dramatic shadows, wide aspect ratio, movie-quality composition",
                category: .lighting, thumbnailImageName: "template-lighting-01"),
        builtIn(uuid: "000000000021", name: String(localized: "ネオン"),
                promptText: "neon light glow, cyberpunk color palette, electric blue and magenta, reflective wet surfaces, night urban scene, LED signage",
                category: .lighting, thumbnailImageName: "template-lighting-02"),
        builtIn(uuid: "000000000022", name: String(localized: "逆光"),
                promptText: "backlit silhouette, rim lighting, halo effect around subject, dramatic contrast, sun directly behind, glowing edges",
                category: .lighting, thumbnailImageName: "template-lighting-03"),
        builtIn(uuid: "000000000023", name: String(localized: "霧・ミスト"),
                promptText: "foggy atmosphere, volumetric mist, diffused soft light, low visibility, mysterious mood, ethereal haze, atmospheric depth",
                category: .lighting, thumbnailImageName: "template-lighting-04"),
        builtIn(uuid: "000000000024", name: String(localized: "ドラマチック影"),
                promptText: "dramatic chiaroscuro, deep black shadows, strong directional light, Rembrandt lighting, high contrast, theatrical mood",
                category: .lighting, thumbnailImageName: "template-lighting-05"),
        builtIn(uuid: "000000000025", name: String(localized: "ソフトライト"),
                promptText: "soft diffused lighting, overcast sky illumination, minimal shadows, even exposure, gentle gradients, flattering skin tones",
                category: .lighting, thumbnailImageName: "template-lighting-06"),
        builtIn(uuid: "000000000026", name: String(localized: "ハードライト"),
                promptText: "hard directional light, sharp defined shadows, high contrast edges, noon sunlight, strong specular highlights, crisp shadow lines",
                category: .lighting, thumbnailImageName: "template-lighting-07"),
        builtIn(uuid: "000000000027", name: String(localized: "ムーディー"),
                promptText: "moody dark atmosphere, low-key lighting, deep shadows, muted desaturated tones, melancholic feel, noir-inspired mood",
                category: .lighting, thumbnailImageName: "template-lighting-08"),
        builtIn(uuid: "000000000028", name: String(localized: "ヴィンテージ"),
                promptText: "vintage retro aesthetic, faded warm tones, sepia undertones, vignette edges, nostalgic color grading, aged film look",
                category: .lighting, thumbnailImageName: "template-lighting-09"),
        builtIn(uuid: "000000000029", name: String(localized: "ファンタジー"),
                promptText: "fantasy ethereal glow, magical particle effects, iridescent light rays, enchanted atmosphere, soft bloom, otherworldly illumination",
                category: .lighting, thumbnailImageName: "template-lighting-10"),
    ]

}
