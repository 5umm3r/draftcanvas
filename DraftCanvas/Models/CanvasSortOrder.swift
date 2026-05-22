import Foundation

// MARK: - CanvasSortOrder

enum CanvasSortOrder: String, CaseIterable, Identifiable {
    case createdAtAscending
    case createdAtDescending
    var id: String { rawValue }
    var label: String {
        switch self {
        case .createdAtAscending: return String(localized: "作成日 古い順")
        case .createdAtDescending: return String(localized: "作成日 新しい順")
        }
    }
    var systemImage: String {
        switch self {
        case .createdAtAscending: return "arrow.up"
        case .createdAtDescending: return "arrow.down"
        }
    }
}
