import SwiftUI

extension ContentView {
    var projectSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("プロジェクト")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.createProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("新規プロジェクト")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $viewModel.selectedProjectID) {
                if !viewModel.favoriteProjects.isEmpty {
                    Section("お気に入り") {
                        ForEach(viewModel.favoriteProjects) { project in
                            projectRowView(for: project)
                        }
                    }
                }
                Section(viewModel.favoriteProjects.isEmpty ? "" : "すべて") {
                    ForEach(viewModel.regularProjects) { project in
                        projectRowView(for: project)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 200)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    func projectRowView(for project: Project) -> some View {
        ProjectRow(
            project: project,
            isEditing: editingProjectID == project.id,
            isGenerating: viewModel.generatingProjectIDs.contains(project.id) || viewModel.exportingProjectID == project.id,
            renamingText: $renamingText,
            onCommitRename: {
                viewModel.renameProject(id: project.id, to: renamingText)
                editingProjectID = nil
            },
            onCancelRename: {
                editingProjectID = nil
            },
            onStop: viewModel.stopServer
        )
        .contentShape(Rectangle())
        .tag(project.id as UUID?)
        .contextMenu {
            Button(project.isFavorite ? "お気に入りから外す" : "お気に入りに追加") {
                viewModel.toggleFavorite(id: project.id)
            }
            Button("名前を変更") {
                renamingText = project.name
                editingProjectID = project.id
            }
            Button("削除", role: .destructive) {
                confirmingDeleteProjectID = project.id
            }
        }
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { isDroppingOnProject[project.id] ?? false },
            set: { isDroppingOnProject[project.id] = $0 }
        )) { providers in
            handleProjectDrop(providers, targetProjectID: project.id)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity((isDroppingOnProject[project.id] ?? false) ? 0.15 : 0))
        )
    }

    func handleProjectDrop(_ providers: [NSItemProvider], targetProjectID: UUID) -> Bool {
        guard let provider = providers.first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let uuidString = obj as? String,
                  let itemID = UUID(uuidString: uuidString) else { return }
            Task { @MainActor in
                guard let item = self.viewModel.items.first(where: { $0.id == itemID }),
                      item.projectID != targetProjectID else { return }
                self.dragDropItemID = itemID
                self.dragDropTargetProjectID = targetProjectID
            }
        }
        return true
    }
}
