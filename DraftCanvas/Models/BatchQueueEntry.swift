import Foundation

struct BatchQueueEntry: Identifiable, Equatable {
    enum Status: Equatable {
        case queued
        case running
        case done
        case failed
    }
    let id: UUID
    var prompt: String
    var count: Int
    var status: Status

    init(id: UUID = UUID(), prompt: String, count: Int = 1, status: Status = .queued) {
        self.id = id
        self.prompt = prompt
        self.count = count
        self.status = status
    }
}
