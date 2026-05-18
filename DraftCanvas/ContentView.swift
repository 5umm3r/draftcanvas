import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @EnvironmentObject var l10n: LocalizationManager
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
    @Environment(\.openSettings) var openSettings
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
        let _ = l10n.locale  // l10n 変化で ContentView を再描画させる
        return VStack(spacing: 0) {
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
                let canvasItems = canvasEntries.compactMap { entry -> ProjectItem? in
                    if case .item(let i) = entry { return i } else { return nil }
                }
                ExpandedImageSheet(item: item, items: canvasItems, viewModel: viewModel) {
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
                if failed > 0 { viewModel.errorToast = String(localized: "\(failed)件の削除に失敗しました") }
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
        .confirmationDialog(
            String(localized: "ChatGPT Free プランでは画像生成を利用できません"),
            isPresented: $viewModel.pendingFreeAccountBlock,
            titleVisibility: .visible
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "画像生成には ChatGPT Plus 以上のプランが必要です。"))
        }
        .confirmationDialog(
            String(localized: "残量が少なくなっています"),
            isPresented: .init(
                get: { viewModel.pendingRateLimitConfirmation != nil },
                set: { if !$0 { viewModel.pendingRateLimitConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation = viewModel.pendingRateLimitConfirmation {
                Button(String(localized: "続行")) {
                    confirmation.resume()
                }
            }
            Button("キャンセル", role: .cancel) {
                viewModel.pendingRateLimitConfirmation = nil
            }
        } message: {
            if let confirmation = viewModel.pendingRateLimitConfirmation {
                Text(String(localized: "残量が少なくなっています (残り \(confirmation.remainingPercent)%%)。生成を続行しますか？"))
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
        .onReceive(NotificationCenter.default.publisher(for: .openLicensesWindow)) { _ in
            openWindow(id: "licenses")
        }
    }
}

// MARK: - Drag & Drop helpers

extension ContentView {

    var dragDropCount: Int {
        !dragDropItemIDs.isEmpty ? dragDropItemIDs.count : (dragDropItemID == nil ? 0 : 1)
    }

    var dragDropDialogTitle: String {
        dragDropCount > 1 ? String(localized: "\(dragDropCount)件を別プロジェクトへ") : String(localized: "アイテムを別プロジェクトへ")
    }

    var dragDropMoveLabel: String {
        dragDropCount > 1 ? String(localized: "\(dragDropCount)件を移動") : String(localized: "移動")
    }

    var dragDropCopyLabel: String {
        dragDropCount > 1 ? String(localized: "\(dragDropCount)件をコピー") : String(localized: "コピー")
    }

    func dragDropMessage(projectName: String) -> String {
        dragDropCount > 1
            ? String(localized: "「\(projectName)」へ\(dragDropCount)件を移動またはコピーしますか？")
            : String(localized: "「\(projectName)」へ移動またはコピーしますか？")
    }

    func performDragDropMove() {
        guard let targetID = dragDropTargetProjectID else { return }
        if !dragDropItemIDs.isEmpty {
            let ids = Set(dragDropItemIDs)
            let failed = viewModel.moveItems(ids: ids, targetProjectID: targetID)
            if failed > 0 { viewModel.errorToast = String(localized: "\(failed)件の移動に失敗しました") }
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
            if failed > 0 { viewModel.errorToast = String(localized: "\(failed)件のコピーに失敗しました") }
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
