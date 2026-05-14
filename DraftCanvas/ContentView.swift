import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow
    @Environment(\.colorScheme) var colorScheme
    @State var isLogWindowVisible = false
    @State var editingProjectID: UUID?
    @State var renamingText = ""
    @State var confirmingDeleteProjectID: UUID?
    @State var isAccountPopoverPresented = false
    @State var showCountPopover = false
    @State var promptIsFocused = false
    @State var promptTextHeight: CGFloat = 76
    @State var canvasZoom: CGFloat = 1.0
    @State var enhanceRotation: Double = 0
    @State var isPromptDropTargeted = false
    @State var isCanvasDropTargeted = false
    @State var dragDropTargetProjectID: UUID?
    @State var dragDropItemID: UUID?
    @State var dragDropItemIDs: [UUID] = []
    @State var isDroppingOnProject: [UUID: Bool] = [:]
    @State var isConfirmingBatchDelete = false
    @State var isCompletionSoundMenuHovered = false
    @State var cardFrames: [UUID: CGRect] = [:]
    @State var marqueeRect: CGRect? = nil
    @State var isDraggingMarquee: Bool = false
    @State var isDragStartedOnCard: Bool = false
    @State var marqueeAdditive: Bool = false
    @State var dragSelectedIDs: Set<UUID> = []
    @State var canvasAutoScroller = CanvasAutoScroller()
    @State var canvasViewportHeight: CGFloat = 600
    @State var showSaveSearchAlert = false
    @State var pendingSidebarSelection: SidebarSelection?
    @State var isPromptHoverExpanded: Bool = false
    @State var hoverExpandTask: Task<Void, Never>? = nil
    @State var hoverCollapseTask: Task<Void, Never>? = nil
    @State var promptFocusTrigger: Bool = false
    @State var expandedItem: ProjectItem? = nil
    @State var confirmingDeleteItemID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            topStatusBar

            Divider()

            HStack(spacing: 0) {
                projectSidebar

                canvasArea
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1000, minHeight: 760)
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorToast {
                ErrorToastView(message: message)
                    .padding(.bottom, 20)
                    .transition(.opacity)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await MainActor.run { viewModel.errorToast = nil }
                        }
                    }
            }
        }
        .overlay {
            if let item = expandedItem {
                ExpandedImageSheet(item: item, viewModel: viewModel) {
                    withAnimation(.easeInOut(duration: 0.2)) { expandedItem = nil }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedItem != nil)
        .animation(.easeInOut(duration: 0.25), value: viewModel.errorToast)
        .onDisappear {
            viewModel.stopServer()
        }
        .alert("プロジェクトを削除しますか？", isPresented: .init(
            get: { confirmingDeleteProjectID != nil },
            set: { if !$0 { confirmingDeleteProjectID = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let id = confirmingDeleteProjectID {
                    viewModel.deleteProject(id: id)
                }
                confirmingDeleteProjectID = nil
            }
            Button("キャンセル", role: .cancel) {
                confirmingDeleteProjectID = nil
            }
        } message: {
            Text("プロジェクトと含まれる全画像を削除します。この操作は取り消せません。")
        }
        .alert(
            "\(viewModel.selectedItemIDs.count)件の画像を削除しますか？",
            isPresented: $isConfirmingBatchDelete
        ) {
            Button("削除", role: .destructive) {
                let ids = viewModel.selectedItemIDs
                let failed = viewModel.deleteItems(ids: ids)
                if failed > 0 { viewModel.errorToast = "\(failed)件の削除に失敗しました" }
                viewModel.isSelectionMode = false
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .confirmationDialog(
            dragDropDialogTitle,
            isPresented: .init(
                get: { dragDropTargetProjectID != nil && (dragDropItemID != nil || !dragDropItemIDs.isEmpty) },
                set: { if !$0 { resetDragDropState() } }
            ),
            titleVisibility: .visible
        ) {
            Button(dragDropMoveLabel) {
                performDragDropMove()
            }
            Button(dragDropCopyLabel) {
                performDragDropCopy()
            }
            Button("キャンセル", role: .cancel) {
                resetDragDropState()
            }
        } message: {
            if let targetID = dragDropTargetProjectID,
               let project = viewModel.projects.first(where: { $0.id == targetID }) {
                Text(dragDropMessage(projectName: project.name))
            }
        }
        .sheet(item: $viewModel.exportRequest) { request in
            ExportOptionsSheet(
                request: request,
                saveFolderName: viewModel.preferredSaveFolder?.lastPathComponent,
                onExport: { settings in
                    if case .batchItems = request.source {
                        viewModel.performBatchExport(request: request, settings: settings)
                    } else {
                        viewModel.performExport(request: request, settings: settings)
                    }
                },
                onCancel: { viewModel.exportRequest = nil }
            )
        }
        .alert("画像を削除しますか？", isPresented: .init(
            get: { confirmingDeleteItemID != nil },
            set: { if !$0 { confirmingDeleteItemID = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let id = confirmingDeleteItemID,
                   let item = viewModel.items.first(where: { $0.id == id }) {
                    viewModel.deleteItem(item)
                }
                confirmingDeleteItemID = nil
            }
            Button("キャンセル", role: .cancel) { confirmingDeleteItemID = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .onChange(of: viewModel.focusPromptTrigger) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                promptFocusTrigger = true
            }
        }
    }
}

// MARK: - Drag & Drop helpers

extension ContentView {

    var dragDropCount: Int {
        !dragDropItemIDs.isEmpty ? dragDropItemIDs.count : (dragDropItemID == nil ? 0 : 1)
    }

    var dragDropDialogTitle: String {
        dragDropCount > 1 ? "\(dragDropCount)件を別プロジェクトへ" : "アイテムを別プロジェクトへ"
    }

    var dragDropMoveLabel: String {
        dragDropCount > 1 ? "\(dragDropCount)件を移動" : "移動"
    }

    var dragDropCopyLabel: String {
        dragDropCount > 1 ? "\(dragDropCount)件をコピー" : "コピー"
    }

    func dragDropMessage(projectName: String) -> String {
        dragDropCount > 1
            ? "「\(projectName)」へ\(dragDropCount)件を移動またはコピーしますか？"
            : "「\(projectName)」へ移動またはコピーしますか？"
    }

    func performDragDropMove() {
        guard let targetID = dragDropTargetProjectID else { return }
        if !dragDropItemIDs.isEmpty {
            let ids = Set(dragDropItemIDs)
            let failed = viewModel.moveItems(ids: ids, targetProjectID: targetID)
            if failed > 0 { viewModel.errorToast = "\(failed)件の移動に失敗しました" }
            viewModel.isSelectionMode = false
        } else if let itemID = dragDropItemID,
                  let item = viewModel.items.first(where: { $0.id == itemID }) {
            viewModel.moveItemToProject(item, targetProjectID: targetID)
        }
        resetDragDropState()
    }

    func performDragDropCopy() {
        guard let targetID = dragDropTargetProjectID else { return }
        if !dragDropItemIDs.isEmpty {
            let ids = Set(dragDropItemIDs)
            let failed = viewModel.copyItems(ids: ids, targetProjectID: targetID)
            if failed > 0 { viewModel.errorToast = "\(failed)件のコピーに失敗しました" }
            viewModel.isSelectionMode = false
        } else if let itemID = dragDropItemID,
                  let item = viewModel.items.first(where: { $0.id == itemID }) {
            viewModel.copyItemToProject(item, targetProjectID: targetID)
        }
        resetDragDropState()
    }

    func resetDragDropState() {
        dragDropItemID = nil
        dragDropItemIDs = []
        dragDropTargetProjectID = nil
    }
}
