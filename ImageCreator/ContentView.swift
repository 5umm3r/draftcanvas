import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
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
    @State var isDroppingOnProject: [UUID: Bool] = [:]

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
        .confirmationDialog(
            "アイテムを別プロジェクトへ",
            isPresented: .init(
                get: { dragDropItemID != nil && dragDropTargetProjectID != nil },
                set: { if !$0 { dragDropItemID = nil; dragDropTargetProjectID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移動") {
                if let itemID = dragDropItemID,
                   let targetID = dragDropTargetProjectID,
                   let item = viewModel.items.first(where: { $0.id == itemID }) {
                    viewModel.moveItemToProject(item, targetProjectID: targetID)
                }
                dragDropItemID = nil
                dragDropTargetProjectID = nil
            }
            Button("コピー") {
                if let itemID = dragDropItemID,
                   let targetID = dragDropTargetProjectID,
                   let item = viewModel.items.first(where: { $0.id == itemID }) {
                    viewModel.copyItemToProject(item, targetProjectID: targetID)
                }
                dragDropItemID = nil
                dragDropTargetProjectID = nil
            }
            Button("キャンセル", role: .cancel) {
                dragDropItemID = nil
                dragDropTargetProjectID = nil
            }
        } message: {
            if let targetID = dragDropTargetProjectID,
               let project = viewModel.projects.first(where: { $0.id == targetID }) {
                Text("「\(project.name)」へ移動またはコピーしますか？")
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
    }
}
