import Foundation

// MARK: - ProjectInputs

struct ProjectInputs: Equatable {
    var prompt: String = ""
    var count: Int = 1
    var concurrency: Int = 1
    var aspectRatio: GenerationAspectRatio = .auto
    var editSource: GenerationEditSource? = nil
    var attachedImage: AttachedImage? = nil
    var model: String = ""
    var reasoningEffort: String = "medium"
}
