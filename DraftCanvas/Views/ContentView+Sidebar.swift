import SwiftUI

// MARK: - Smart Project views

struct SmartSectionHeader: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var showCreation = false

    var body: some View {
        HStack {
            Text("スマート")
            Spacer()
            Button {
                showCreation = true
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("スマートプロジェクトを作成")
        }
        .sheet(isPresented: $showCreation) {
            SmartProjectCreationSheet(viewModel: viewModel)
        }
    }
}

struct SmartProjectRow: View {
    let smart: SmartProject
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var showEdit = false

    var body: some View {
        Button {
            viewModel.selectSmartProject(id: smart.id)
        } label: {
            Label(smart.name, systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled(true)
        .listRowBackground(
            viewModel.selectedSmartProjectID == smart.id
                ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.18))
                : nil
        )
        .contextMenu {
            Button("条件を編集") { showEdit = true }
            Divider()
            Button("削除", role: .destructive) { viewModel.deleteSmartProject(id: smart.id) }
        }
        .sheet(isPresented: $showEdit) {
            SmartProjectCreationSheet(viewModel: viewModel, existingSmart: smart)
        }
    }
}

// MARK: - Sidebar

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

            List(selection: Binding(
                get: { viewModel.selectedProjectID },
                set: { id in
                    viewModel.selectedSmartProjectID = nil
                    viewModel.selectedProjectID = id
                }
            )) {
                if !viewModel.favoriteProjects.isEmpty {
                    Section("お気に入り") {
                        ForEach(viewModel.favoriteProjects) { project in
                            projectRowView(for: project)
                        }
                    }
                }
                Section {
                    ForEach(viewModel.smartProjects) { smart in
                        SmartProjectRow(smart: smart, viewModel: viewModel)
                    }
                } header: {
                    SmartSectionHeader(viewModel: viewModel)
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
            guard let payload = obj as? String else { return }
            let ids: [UUID] = payload
                .split(whereSeparator: { $0.isNewline })
                .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
            guard !ids.isEmpty else { return }
            Task { @MainActor in
                let validIDs = ids.filter { id in
                    self.viewModel.items.first(where: { $0.id == id })?.projectID != targetProjectID
                }
                guard !validIDs.isEmpty else { return }
                if validIDs.count == 1 {
                    self.dragDropItemID = validIDs[0]
                    self.dragDropItemIDs = []
                } else {
                    self.dragDropItemIDs = validIDs
                    self.dragDropItemID = nil
                }
                self.dragDropTargetProjectID = targetProjectID
            }
        }
        return true
    }
}
