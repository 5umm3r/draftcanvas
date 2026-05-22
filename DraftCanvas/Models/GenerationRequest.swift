import Foundation

struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int
    var concurrency: Int
    var aspectRatio: GenerationAspectRatio = .auto
    var editSource: GenerationEditSource? = nil
    var attachedImagePath: String? = nil
    var attachedImageKind: AttachmentKind = .regular
    var model: String = ""
    var reasoningEffort: String = "medium"
    var translateToEnglish: Bool = false
    var normalizedPrompt: String? = nil

    var normalizedCount: Int {
        min(max(count, 1), 24)
    }

    var normalizedConcurrency: Int {
        min(max(concurrency, 1), normalizedCount)
    }

    var normalizedGenerationBrief: String? {
        guard translateToEnglish else { return nil }
        let trimmed = normalizedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum InpaintPurpose {
    case edit
    case remove
}

struct GenerationEditSource: Equatable {
    var projectItemID: UUID
    var filePath: String
    var originalPrompt: String
    var maskFilePath: String?
    var compositeFilePath: String?
    var inpaintPurpose: InpaintPurpose

    var isInpainting: Bool { maskFilePath != nil }

    init(
        projectItemID: UUID,
        filePath: String,
        originalPrompt: String,
        maskFilePath: String? = nil,
        compositeFilePath: String? = nil,
        inpaintPurpose: InpaintPurpose = .edit
    ) {
        self.projectItemID = projectItemID
        self.filePath = filePath
        self.originalPrompt = originalPrompt
        self.maskFilePath = maskFilePath
        self.compositeFilePath = compositeFilePath
        self.inpaintPurpose = inpaintPurpose
    }

    static func == (lhs: GenerationEditSource, rhs: GenerationEditSource) -> Bool {
        lhs.projectItemID == rhs.projectItemID &&
        lhs.filePath == rhs.filePath &&
        lhs.originalPrompt == rhs.originalPrompt &&
        lhs.maskFilePath == rhs.maskFilePath &&
        lhs.compositeFilePath == rhs.compositeFilePath
    }
}
