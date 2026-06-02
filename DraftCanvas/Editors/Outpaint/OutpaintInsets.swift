import Foundation

struct OutpaintTarget: Identifiable {
    let id: UUID
    let item: ProjectItem
    var initialInsets: OutpaintInsets

    init(item: ProjectItem, initialInsets: OutpaintInsets = .zero) {
        self.id = UUID()
        self.item = item
        self.initialInsets = initialInsets
    }
}

struct OutpaintInsets: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var left: CGFloat = 0
    var right: CGFloat = 0

    static let zero = OutpaintInsets()

    var isEmpty: Bool {
        top == 0 && bottom == 0 && left == 0 && right == 0
    }

    func expandedSize(from original: CGSize) -> CGSize {
        CGSize(
            width: original.width + left + right,
            height: original.height + top + bottom
        )
    }
}
