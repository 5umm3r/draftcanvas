import Foundation

enum CanvasMoveDirection {
    case left, right, up, down
}

extension DraftCanvasViewModel {
    private var isCanvasNavigationEnabled: Bool {
        !isSelectionMode && selectedItemIDs.isEmpty
    }

    @discardableResult
    func moveCanvasSelection(direction: CanvasMoveDirection, columns: Int) -> Bool {
        // 選択モード中・複数選択中は無効
        guard isCanvasNavigationEnabled else { return false }
        let items = displayedItemsSnapshot
        guard !items.isEmpty else { return false }

        // 選択ゼロなら先頭をセット
        guard let cur = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == cur }) else {
            selectedItemID = items[0].id
            selectedJobID = nil
            return true
        }

        assert(columns > 0, "columns must be positive")
        let next: Int
        switch direction {
        case .left:  next = idx - 1
        case .right: next = idx + 1
        case .up:    next = idx - max(1, columns)
        case .down:  next = idx + max(1, columns)
        }

        // 境界クランプ (ループしない)
        guard next >= 0, next < items.count else { return false }
        selectedItemID = items[next].id
        selectedJobID = nil
        return true
    }

    var canvasPreviewTarget: ProjectItem? {
        guard isCanvasNavigationEnabled else { return nil }
        guard let id = selectedItemID else { return nil }
        return displayedItemsSnapshot.first(where: { $0.id == id })
    }
}
