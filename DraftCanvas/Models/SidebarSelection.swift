import Foundation

// MARK: - SidebarSelection

enum SidebarSelection: Codable, Equatable, Hashable {
    case project(UUID)
    case filtering(UUID)
    case allImages
    case none
    case search

    private enum OuterKey: String, CodingKey { case project, filtering, smart, allImages, none }
    private enum InnerKey: String, CodingKey { case _0 }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKey.self)
        if outer.contains(.project) {
            let inner = try outer.nestedContainer(keyedBy: InnerKey.self, forKey: .project)
            self = .project(try inner.decode(UUID.self, forKey: ._0))
        } else if outer.contains(.filtering) {
            let inner = try outer.nestedContainer(keyedBy: InnerKey.self, forKey: .filtering)
            self = .filtering(try inner.decode(UUID.self, forKey: ._0))
        } else if outer.contains(.smart) {
            let inner = try outer.nestedContainer(keyedBy: InnerKey.self, forKey: .smart)
            self = .filtering(try inner.decode(UUID.self, forKey: ._0))
        } else if outer.contains(.allImages) {
            self = .allImages
        } else {
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var outer = encoder.container(keyedBy: OuterKey.self)
        switch self {
        case .project(let id):
            var inner = outer.nestedContainer(keyedBy: InnerKey.self, forKey: .project)
            try inner.encode(id, forKey: ._0)
        case .filtering(let id):
            var inner = outer.nestedContainer(keyedBy: InnerKey.self, forKey: .filtering)
            try inner.encode(id, forKey: ._0)
        case .allImages:
            try outer.encode(true, forKey: .allImages)
        case .none:
            try outer.encode(true, forKey: .none)
        case .search:
            // 検索モードは永続化しない。起動時は .none にフォールバック
            try outer.encode(true, forKey: .none)
        }
    }
}
