import Foundation

enum PromptTemplateCategory: String, Codable, CaseIterable, Identifiable {
    case style    = "style"
    case photo    = "photo"
    case lighting = "lighting"
    case quality  = "quality"
    case user     = "user"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .style:    return String(localized: "画風・スタイル")
        case .photo:    return String(localized: "写真・カメラ")
        case .lighting: return String(localized: "ライティング・雰囲気")
        case .quality:  return String(localized: "品質・構図")
        case .user:     return String(localized: "マイテンプレート")
        }
    }

    var systemImage: String {
        switch self {
        case .style:    return "paintpalette"
        case .photo:    return "camera"
        case .lighting: return "light.max"
        case .quality:  return "sparkle.magnifyingglass"
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

    init(id: UUID = UUID(), name: String, promptText: String, isBuiltIn: Bool = false, createdAt: Date = Date(), category: PromptTemplateCategory = .user) {
        self.id = id
        self.name = name
        self.promptText = promptText
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        promptText = try container.decode(String.self, forKey: .promptText)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        category = try container.decodeIfPresent(PromptTemplateCategory.self, forKey: .category) ?? .user
    }
}

// MARK: - Built-in Presets

extension PromptTemplate {
    private static func builtIn(uuid: String, name: String, promptText: String, category: PromptTemplateCategory) -> PromptTemplate {
        PromptTemplate(
            id: UUID(uuidString: "00000001-0000-0000-0000-\(uuid)")!,
            name: name,
            promptText: promptText,
            isBuiltIn: true,
            category: category
        )
    }

    static let builtIns: [PromptTemplate] = stylePresets + photoPresets + lightingPresets + qualityPresets

    // MARK: 画風・スタイル

    private static let stylePresets: [PromptTemplate] = [
        builtIn(uuid: "000000000001", name: String(localized: "水彩画風"),
                promptText: "watercolor painting style, soft watercolor washes, translucent layers, paper texture visible, delicate brushwork, bleeding ink edges",
                category: .style),
        builtIn(uuid: "000000000002", name: String(localized: "油絵風"),
                promptText: "oil painting style, thick impasto brushstrokes, rich saturated colors, visible canvas texture, dramatic chiaroscuro lighting",
                category: .style),
        builtIn(uuid: "000000000003", name: String(localized: "フラットイラスト"),
                promptText: "flat design illustration, clean vector-like style, bold solid colors, minimal shading, simple geometric shapes",
                category: .style),
        builtIn(uuid: "000000000004", name: String(localized: "ピクセルアート"),
                promptText: "pixel art style, 32x32 sprite aesthetic, limited 16-color palette, crisp hard edges, no anti-aliasing, retro video game",
                category: .style),
        builtIn(uuid: "000000000005", name: String(localized: "ラインアート"),
                promptText: "clean line art, precise ink drawing, bold outlines, minimal hatching, black and white with selective color accents",
                category: .style),
        builtIn(uuid: "000000000006", name: String(localized: "鉛筆スケッチ"),
                promptText: "pencil sketch drawing, graphite texture, rough construction lines, cross-hatching shading, artistic study, sketchbook paper",
                category: .style),
        builtIn(uuid: "000000000007", name: String(localized: "アニメ風"),
                promptText: "anime illustration style, cel-shaded coloring, large expressive eyes, clean outlines, vibrant color palette, manga-inspired composition",
                category: .style),
        builtIn(uuid: "000000000008", name: String(localized: "浮世絵風"),
                promptText: "ukiyo-e woodblock print style, flat color areas, bold black outlines, traditional Japanese composition, wave patterns, washi paper texture",
                category: .style),
        builtIn(uuid: "000000000009", name: String(localized: "ローポリ3D"),
                promptText: "low-poly 3D render, geometric faceted surfaces, minimal polygon count, flat shading, pastel color palette, abstract simplified forms",
                category: .style),
        builtIn(uuid: "00000000000a", name: String(localized: "コミック風"),
                promptText: "comic book illustration, bold ink outlines, halftone dot shading, dynamic action poses, speech bubble layout, vivid primary colors",
                category: .style),
    ]

    // MARK: 写真・カメラ

    private static let photoPresets: [PromptTemplate] = [
        builtIn(uuid: "000000000010", name: String(localized: "写真風"),
                promptText: "photorealistic photography, shot on 85mm lens, natural soft lighting, shallow depth of field, high resolution detail",
                category: .photo),
        builtIn(uuid: "000000000011", name: String(localized: "ポートレート"),
                promptText: "portrait photography, 50mm f/1.4 lens, soft bokeh background, studio lighting, catchlight in eyes, skin detail preserved",
                category: .photo),
        builtIn(uuid: "000000000012", name: String(localized: "マクロ撮影"),
                promptText: "macro photography, extreme close-up, razor-thin depth of field, intricate surface details, ring light illumination, 1:1 magnification",
                category: .photo),
        builtIn(uuid: "000000000013", name: String(localized: "俯瞰"),
                promptText: "bird's-eye view, top-down perspective, aerial photography, flat lay composition, overhead angle, symmetrical arrangement",
                category: .photo),
        builtIn(uuid: "000000000014", name: String(localized: "魚眼レンズ"),
                promptText: "fisheye lens effect, ultra-wide 8mm focal length, barrel distortion, 180-degree field of view, spherical perspective warp",
                category: .photo),
        builtIn(uuid: "000000000015", name: String(localized: "ボケ"),
                promptText: "beautiful bokeh, f/1.2 wide aperture, soft circular highlights, creamy out-of-focus areas, dreamy background blur, light orbs",
                category: .photo),
        builtIn(uuid: "000000000016", name: String(localized: "ゴールデンアワー"),
                promptText: "golden hour photography, warm amber sunlight, long soft shadows, lens flare, backlit subject, magical warm tone",
                category: .photo),
        builtIn(uuid: "000000000017", name: String(localized: "長時間露光"),
                promptText: "long exposure photography, motion blur trails, silky smooth water, light painting streaks, 30-second shutter, tripod-steady composition",
                category: .photo),
        builtIn(uuid: "000000000018", name: String(localized: "フィルムグレイン"),
                promptText: "analog film grain, Kodak Portra 400 color profile, slight color shift, organic noise texture, vintage analog feel, light leaks",
                category: .photo),
        builtIn(uuid: "000000000019", name: String(localized: "ティルトシフト"),
                promptText: "tilt-shift photography, miniature effect, selective focus band, toy-like appearance, saturated colors, diorama perspective",
                category: .photo),
    ]

    // MARK: ライティング・雰囲気

    private static let lightingPresets: [PromptTemplate] = [
        builtIn(uuid: "000000000020", name: String(localized: "シネマティック"),
                promptText: "cinematic lighting, anamorphic lens flare, film color grading, dramatic shadows, wide aspect ratio, movie-quality composition",
                category: .lighting),
        builtIn(uuid: "000000000021", name: String(localized: "ネオン"),
                promptText: "neon light glow, cyberpunk color palette, electric blue and magenta, reflective wet surfaces, night urban scene, LED signage",
                category: .lighting),
        builtIn(uuid: "000000000022", name: String(localized: "逆光"),
                promptText: "backlit silhouette, rim lighting, halo effect around subject, dramatic contrast, sun directly behind, glowing edges",
                category: .lighting),
        builtIn(uuid: "000000000023", name: String(localized: "霧・ミスト"),
                promptText: "foggy atmosphere, volumetric mist, diffused soft light, low visibility, mysterious mood, ethereal haze, atmospheric depth",
                category: .lighting),
        builtIn(uuid: "000000000024", name: String(localized: "ドラマチック影"),
                promptText: "dramatic chiaroscuro, deep black shadows, strong directional light, Rembrandt lighting, high contrast, theatrical mood",
                category: .lighting),
        builtIn(uuid: "000000000025", name: String(localized: "ソフトライト"),
                promptText: "soft diffused lighting, overcast sky illumination, minimal shadows, even exposure, gentle gradients, flattering skin tones",
                category: .lighting),
        builtIn(uuid: "000000000026", name: String(localized: "ハードライト"),
                promptText: "hard directional light, sharp defined shadows, high contrast edges, noon sunlight, strong specular highlights, crisp shadow lines",
                category: .lighting),
        builtIn(uuid: "000000000027", name: String(localized: "ムーディー"),
                promptText: "moody dark atmosphere, low-key lighting, deep shadows, muted desaturated tones, melancholic feel, noir-inspired mood",
                category: .lighting),
        builtIn(uuid: "000000000028", name: String(localized: "ヴィンテージ"),
                promptText: "vintage retro aesthetic, faded warm tones, sepia undertones, vignette edges, nostalgic color grading, aged film look",
                category: .lighting),
        builtIn(uuid: "000000000029", name: String(localized: "ファンタジー"),
                promptText: "fantasy ethereal glow, magical particle effects, iridescent light rays, enchanted atmosphere, soft bloom, otherworldly illumination",
                category: .lighting),
    ]

    // MARK: 品質・構図

    private static let qualityPresets: [PromptTemplate] = [
        builtIn(uuid: "000000000030", name: String(localized: "高精細"),
                promptText: "ultra high resolution, extremely detailed, sharp focus throughout, fine texture rendering, professional quality, 4K clarity",
                category: .quality),
        builtIn(uuid: "000000000031", name: String(localized: "8Kレンダー"),
                promptText: "8K ultra HD render, ray-traced global illumination, physically-based materials, subsurface scattering, photon-mapped caustics",
                category: .quality),
        builtIn(uuid: "000000000032", name: String(localized: "浅い被写界深度"),
                promptText: "shallow depth of field, subject in sharp focus, foreground and background blur, smooth bokeh transition, f/1.4 aperture effect",
                category: .quality),
        builtIn(uuid: "000000000033", name: String(localized: "三分割構図"),
                promptText: "rule of thirds composition, subject placed at intersection points, balanced negative space, guided visual flow, professional framing",
                category: .quality),
        builtIn(uuid: "000000000034", name: String(localized: "ミニマル"),
                promptText: "minimalist composition, vast negative space, single focal element, clean uncluttered background, reduced color palette, serene simplicity",
                category: .quality),
        builtIn(uuid: "000000000035", name: String(localized: "シンメトリー"),
                promptText: "perfect symmetrical composition, mirror-image balance, centered subject, Wes Anderson framing, architectural precision, bilateral symmetry",
                category: .quality),
        builtIn(uuid: "000000000036", name: String(localized: "ワイドショット"),
                promptText: "extreme wide shot, vast landscape, subject small in frame, environmental context, epic scale, panoramic composition",
                category: .quality),
        builtIn(uuid: "000000000037", name: String(localized: "クローズアップ"),
                promptText: "extreme close-up shot, filling the frame, intimate detail, tight crop, emotional intensity, texture emphasis",
                category: .quality),
        builtIn(uuid: "000000000038", name: String(localized: "ダイナミックアングル"),
                promptText: "dynamic camera angle, dramatic low angle, foreshortening effect, diagonal composition, sense of motion, action perspective",
                category: .quality),
        builtIn(uuid: "000000000039", name: String(localized: "アイソメトリック"),
                promptText: "isometric view, 30-degree angle projection, no perspective convergence, technical illustration style, uniform scale, diorama-like",
                category: .quality),
    ]
}
