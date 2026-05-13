import SwiftUI

// MARK: - Filtering Project views

struct FilteringSectionHeader: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @Binding var isExpanded: Bool
    @State private var showCreation = false

    var body: some View {
        HStack(spacing: 0) {
            Text("フィルタリング")
            Spacer()
            Button { showCreation = true } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("フィルタリングプロジェクトを作成")
            Spacer().frame(width: 12)
            Button { isExpanded.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(isExpanded ? .zero : .degrees(-90))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)
        }
        .sheet(isPresented: $showCreation) {
            FilteringProjectCreationSheet(viewModel: viewModel)
        }
    }
}

struct FilteringProjectRow: View {
    let filtering: FilteringProject
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var showEdit = false

    var body: some View {
        Label(filtering.name, systemImage: "line.3.horizontal.decrease.circle")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button("条件を編集") { showEdit = true }
                Divider()
                Button("削除", role: .destructive) { viewModel.deleteFilteringProject(id: filtering.id) }
            }
            .sheet(isPresented: $showEdit) {
                FilteringProjectCreationSheet(viewModel: viewModel, existingFiltering: filtering)
            }
    }
}

// MARK: - All Images row

struct AllImagesRow: View {
    var body: some View {
        Label("すべての画像", systemImage: "photo.on.rectangle.angled")
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

// MARK: - Project section header

struct ProjectSectionHeader: View {
    let onAdd: () -> Void
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("プロジェクト")
            Spacer()
            Button { onAdd() } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("新規プロジェクト")
            Spacer().frame(width: 12)
            Button { isExpanded.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(isExpanded ? .zero : .degrees(-90))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)
        }
    }
}

// MARK: - Sidebar

extension ContentView {
    var projectSidebar: some View {
        VStack(spacing: 0) {
            sidebarSearchBar
            Divider()
            List(selection: sidebarSelectionBinding) {
                Section {
                    if viewModel.expandedSections["favorites"] ?? true {
                        ForEach(viewModel.favoriteProjects) { project in
                            projectRowView(for: project)
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("お気に入り")
                        Spacer()
                        Button { viewModel.toggleSection("favorites") } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect((viewModel.expandedSections["favorites"] ?? true) ? .zero : .degrees(-90))
                                .animation(.easeInOut(duration: 0.15), value: viewModel.expandedSections["favorites"] ?? true)
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 8)
                    }
                }

                Section {
                    if viewModel.expandedSections["filtering"] ?? true {
                        ForEach(viewModel.filteringProjects) { filtering in
                            FilteringProjectRow(filtering: filtering, viewModel: viewModel)
                                .tag(SidebarSelection.filtering(filtering.id))
                        }
                    }
                } header: {
                    FilteringSectionHeader(viewModel: viewModel, isExpanded: bindingFor("filtering"))
                }

                Section {
                    AllImagesRow()
                        .tag(SidebarSelection.allImages)
                }

                Section {
                    if viewModel.expandedSections["projects"] ?? true {
                        ForEach(viewModel.regularProjects) { project in
                            projectRowView(for: project)
                        }
                    }
                } header: {
                    ProjectSectionHeader(onAdd: { viewModel.createProject() }, isExpanded: bindingFor("projects"))
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListHeaderHeight, 0)
            .background(.regularMaterial)
            .onKeyPress(.return) {
                guard editingProjectID == nil,
                      case .project(let id) = viewModel.sidebarSelection,
                      let project = viewModel.projects.first(where: { $0.id == id })
                else { return .ignored }
                renamingText = project.name
                editingProjectID = id
                return .handled
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
            }
        }
        .frame(width: 200)
        .alert("検索結果を保存しますか？", isPresented: $showSaveSearchAlert) {
            Button("保存して移動") {
                let dest = pendingSidebarSelection
                viewModel.saveCurrentSearchAsFilteringProject(thenSelect: dest)
                pendingSidebarSelection = nil
            }
            Button("保存せずに移動", role: .destructive) {
                let dest = pendingSidebarSelection
                viewModel.exitSearchMode(clearDraft: true)
                if let dest { viewModel.sidebarSelection = dest }
                pendingSidebarSelection = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingSidebarSelection = nil
            }
        } message: {
            Text("「\(viewModel.sidebarSearchCommitted)」の検索結果をフィルタリングプロジェクトとして保存できます。")
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("検索", text: $viewModel.sidebarSearchDraft)
                .textFieldStyle(.plain)
                .onChange(of: viewModel.sidebarSearchDraft) { _, new in
                    viewModel.onSearchDraftChanged(new)
                }
            if !viewModel.sidebarSearchDraft.isEmpty {
                Button {
                    viewModel.exitSearchMode(clearDraft: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                Button {
                    viewModel.saveCurrentSearchAsFilteringProject()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("この検索条件を保存")
                .disabled(viewModel.sidebarSearchCommitted.isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var sidebarSelectionBinding: Binding<SidebarSelection> {
        Binding(
            get: { viewModel.sidebarSelection },
            set: { newValue in
                if case .search = newValue { return }
                if viewModel.isSearchActive {
                    if case .none = newValue { return }
                    pendingSidebarSelection = newValue
                    showSaveSearchAlert = true
                    return
                }
                viewModel.sidebarSelection = newValue
            }
        )
    }

    private func bindingFor(_ key: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.expandedSections[key] ?? true },
            set: { _ in viewModel.toggleSection(key) }
        )
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
        .tag(SidebarSelection.project(project.id))
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
