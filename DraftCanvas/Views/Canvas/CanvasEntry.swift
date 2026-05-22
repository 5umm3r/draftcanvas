import SwiftUI

enum CanvasEntry: Identifiable {
    case item(ProjectItem)
    case job(GenerationJob)

    var id: UUID {
        switch self {
        case .item(let i): return i.id
        case .job(let j): return j.id
        }
    }

    var itemID: UUID? {
        if case .item(let item) = self { return item.id }
        return nil
    }
}
