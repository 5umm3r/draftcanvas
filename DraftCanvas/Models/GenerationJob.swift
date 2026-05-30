import Foundation

enum GenerationFailureKind: String, Codable {
    case rateLimited
    case timeout
    case other
}

enum GenerationJobStatus: String {
    case queued
    case running
    case succeeded
    case failed

    var title: String {
        switch self {
        case .queued:
            return String(localized: "待機中")
        case .running:
            return String(localized: "生成中")
        case .succeeded:
            return String(localized: "完了")
        case .failed:
            return String(localized: "失敗")
        }
    }
}

struct GenerationJob: Identifiable, Equatable {
    let id: UUID
    let index: Int
    var prompt: String
    var aspectRatio: GenerationAspectRatio
    var status: GenerationJobStatus
    var imageData: Data?
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?
    var hitRateLimitDuringRun: Bool
    var isFreeAccountBlocked: Bool
    var failureKind: GenerationFailureKind?
    var runID: UUID?

    init(
        id: UUID = UUID(),
        index: Int,
        prompt: String,
        aspectRatio: GenerationAspectRatio,
        status: GenerationJobStatus = .queued,
        imageData: Data? = nil,
        revisedPrompt: String? = nil,
        logs: [String] = [],
        errorMessage: String? = nil,
        hitRateLimitDuringRun: Bool = false,
        isFreeAccountBlocked: Bool = false,
        failureKind: GenerationFailureKind? = nil,
        runID: UUID? = nil
    ) {
        self.id = id
        self.index = index
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.status = status
        self.imageData = imageData
        self.revisedPrompt = revisedPrompt
        self.logs = logs
        self.errorMessage = errorMessage
        self.hitRateLimitDuringRun = hitRateLimitDuringRun
        self.isFreeAccountBlocked = isFreeAccountBlocked
        self.failureKind = failureKind
        self.runID = runID
    }
}
