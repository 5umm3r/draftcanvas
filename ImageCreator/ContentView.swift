import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isLogWindowVisible = false
    @State private var editingProjectID: UUID?
    @State private var renamingText = ""
    @State private var confirmingDeleteProjectID: UUID?
    @State private var isAccountPopoverPresented = false
    @State private var promptIsFocused = false
    @State private var canvasZoom: CGFloat = 1.0

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
    }

    // MARK: - Top Bar

    private var topStatusBar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.chooseSaveFolder) {
                Label("保存先", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("保存先フォルダ: \(viewModel.preferredSaveFolderLabel)")

            Button(action: toggleLogWindow) {
                Label("ログ", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 16)

            usagePill(
                systemName: "clock",
                label: viewModel.accountUsageStatus.primaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.primaryUsageRemainingFraction,
                resetText: viewModel.accountUsageStatus.primaryResetText
            )
            usagePill(
                systemName: "calendar",
                label: viewModel.accountUsageStatus.secondaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.secondaryUsageRemainingFraction,
                resetText: viewModel.accountUsageStatus.secondaryResetText
            )

            Button {
                viewModel.refreshAccountUsage()
            } label: {
                if viewModel.isRefreshingAccountUsage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .help("アカウントと使用量を更新")
            .disabled(viewModel.isRefreshingAccountUsage)

            Divider()
                .frame(height: 22)

            Button {
                isAccountPopoverPresented.toggle()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isAccountPopoverPresented, arrowEdge: .bottom) {
                AccountPopover(status: viewModel.accountUsageStatus)
            }

            planBadge
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.white.opacity(0.86))
    }

    private var planBadge: some View {
        Text(viewModel.accountUsageStatus.planLabel)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }

    // MARK: - Project Sidebar

    private var projectSidebar: some View {
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
                ForEach(viewModel.projects) { project in
                    ProjectRow(
                        project: project,
                        isEditing: editingProjectID == project.id,
                        isGenerating: viewModel.generatingProjectIDs.contains(project.id),
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
                        Button("名前を変更") {
                            renamingText = project.name
                            editingProjectID = project.id
                        }
                        Button("削除", role: .destructive) {
                            confirmingDeleteProjectID = project.id
                        }
                    }
                }
                .onMove { from, to in
                    viewModel.moveProject(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 200)
        .background(.white.opacity(0.86))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        ZStack(alignment: .bottom) {
            canvas

            promptPanel
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
    }

    private var canvas: some View {
        ZStack {
            Color(red: 0.90, green: 0.90, blue: 0.92)

            if viewModel.projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36, weight: .medium))
                    Text("「＋」でプロジェクトを作成するか\nプロンプトを入力して送信してください")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 120)
            } else if canvasEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .medium))
                    Text("プロンプトを入力して生成してください")
                        .font(.title3.weight(.semibold))
                    Text("生成結果はこのキャンバスに並びます")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 120)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220 * canvasZoom), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(canvasEntries) { entry in
                            canvasCard(for: entry)
                        }
                    }
                    .padding(.top, 72)
                    .padding(.horizontal, 90)
                    .padding(.bottom, 220)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !viewModel.projects.isEmpty && !canvasEntries.isEmpty {
                CanvasZoomControl(zoom: $canvasZoom)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
    }

    private var canvasEntries: [CanvasEntry] {
        let persistedItems = viewModel.itemsForSelectedProject.map { CanvasEntry.item($0) }
        let inProgressJobs = viewModel.isGeneratingForSelected ? viewModel.currentJobs.map { CanvasEntry.job($0) } : []
        return persistedItems + inProgressJobs
    }

    // MARK: - Canvas Cards

    @ViewBuilder
    private func canvasCard(for entry: CanvasEntry) -> some View {
        switch entry {
        case .item(let item):
            itemCard(item)
        case .job(let job):
            generationCard(job)
        }
    }

    private func itemCard(_ item: ProjectItem) -> some View {
        Button {
            viewModel.selectedItemID = (viewModel.selectedItemID == item.id) ? nil : item.id
            viewModel.selectedJobID = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    checkerboard
                    previewForItem(item)
                }
                .frame(width: 220 * canvasZoom, height: 220 * canvasZoom)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let sourceID = item.editedFromItemID,
                       let sourceItem = viewModel.items.first(where: { $0.id == sourceID }),
                       let sourceImage = viewModel.cachedImage(for: sourceItem) {
                        Image(nsImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                            }
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            viewModel.selectedItemID == item.id ? Color.accentColor : Color.black.opacity(0.10),
                            lineWidth: viewModel.selectedItemID == item.id ? 3 : 1
                        )
                }

                HStack {
                    Text(item.createdAt, style: .time)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("#\(String(format: "%02d", viewModel.ordinalForItem(item, in: item.projectID)))")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.10))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: .init(
            get: { viewModel.selectedItemID == item.id },
            set: { if !$0 { viewModel.selectedItemID = nil } }
        )) {
            ItemDetailPopover(item: item, viewModel: viewModel)
        }
    }

    private func generationCard(_ job: GenerationJob) -> some View {
        Button {
            viewModel.selectedJobID = (viewModel.selectedJobID == job.id) ? nil : job.id
            viewModel.selectedItemID = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    checkerboard
                    preview(for: job)
                }
                .frame(width: 220 * canvasZoom, height: 220 * canvasZoom)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            viewModel.selectedJobID == job.id ? Color.accentColor : Color.black.opacity(0.10),
                            lineWidth: viewModel.selectedJobID == job.id ? 3 : 1
                        )
                }

                HStack {
                    Text("#\(job.index + 1)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    StatusBadge(status: job.status)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: .init(
            get: { viewModel.selectedJobID == job.id },
            set: { if !$0 { viewModel.selectedJobID = nil } }
        )) {
            GenerationDetailPopover(job: job, viewModel: viewModel)
        }
    }

    // MARK: - Previews

    @ViewBuilder
    private func previewForItem(_ item: ProjectItem) -> some View {
        if let nsImage = viewModel.cachedImage(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.square")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("プレビューを読み込めません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func preview(for job: GenerationJob) -> some View {
        if let imageData = job.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else if job.status == .failed {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(job.errorMessage ?? "生成に失敗しました")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        } else {
            GenerationProgressView(onStop: viewModel.stopServer)
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let side: CGFloat = 18
            for x in stride(from: CGFloat(0), to: size.width, by: side) {
                for y in stride(from: CGFloat(0), to: size.height, by: side) {
                    let isDark = (Int(x / side) + Int(y / side)).isMultiple(of: 2)
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    context.fill(Path(rect), with: .color(isDark ? Color.white : Color.black.opacity(0.045)))
                }
            }
        }
    }

    // MARK: - Prompt Panel

    private var promptPanel: some View {
        VStack(spacing: 0) {
            if viewModel.currentInputs.editSource != nil {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Text("再編集モード")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("解除") {
                        viewModel.cancelEditingHistoryItem()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.10))

                Divider()
            }

            PromptTextView(text: viewModel.binding(for: \.prompt), isFocused: $promptIsFocused)
                .frame(height: 76)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .overlay(alignment: .topLeading) {
                    if viewModel.currentInputs.prompt.isEmpty && !promptIsFocused {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            HStack(spacing: 16) {
                Menu {
                    ForEach(GenerationAspectRatio.allCases) { ar in
                        Button {
                            viewModel.binding(for: \.aspectRatio).wrappedValue = ar
                        } label: {
                            Text("\(ar.title) \(ar.value)")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "aspectratio")
                            .font(.system(size: 13))
                        Text(viewModel.currentInputs.aspectRatio.value)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("アスペクト比")

                CounterControl(
                    systemImage: "square.stack",
                    label: "枚数",
                    value: viewModel.binding(for: \.count),
                    range: 1...24,
                    helpText: "枚数"
                )

                CounterControl(
                    systemImage: "square.split.2x1",
                    label: "並列",
                    value: viewModel.binding(for: \.concurrency),
                    range: 1...8,
                    helpText: "並列実行数"
                )

                Spacer()

                Button {
                    viewModel.generate()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(!viewModel.canGenerate)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: 780)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    // MARK: - Usage Widgets

    private func usagePill(
        systemName: String,
        label: String,
        remainingFraction: Double?,
        resetText: String? = nil
    ) -> some View {
        return HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()

            usageProgressBar(value: remainingFraction)

            if let resetText {
                Text(resetText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(Capsule())
    }

    private func usageProgressBar(value: Double?) -> some View {
        let progress = min(1, max(0, value ?? 0))

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.12))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(value == nil ? 0 : 0.82))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(width: 52, height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private func toggleLogWindow() {
        if isLogWindowVisible {
            dismissWindow(id: "logs")
        } else {
            openWindow(id: "logs")
        }
        isLogWindowVisible.toggle()
    }
}

// MARK: - Canvas Entry

private enum CanvasEntry: Identifiable {
    case item(ProjectItem)
    case job(GenerationJob)

    var id: UUID {
        switch self {
        case .item(let i): return i.id
        case .job(let j): return j.id
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: Project
    let isEditing: Bool
    let isGenerating: Bool
    @Binding var renamingText: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onStop: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        if isEditing {
            TextField("プロジェクト名", text: $renamingText, onCommit: onCommitRename)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { onCancelRename() }
                .onAppear { isFocused = true }
        } else {
            HStack(spacing: 6) {
                Text(project.name)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isGenerating {
                    if isHovering {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }
}

// MARK: - Popovers

struct GenerationDetailPopover: View {
    let job: GenerationJob
    @ObservedObject var viewModel: ImageCreatorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("詳細")
                .font(.headline)

            DetailRow(label: "Status", value: job.status.title)
            DetailRow(label: "Prompt", value: job.prompt)

            if let revisedPrompt = job.revisedPrompt {
                DetailRow(label: "Revised", value: revisedPrompt)
            }
            if let errorMessage = job.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            Divider()

            Button {
                viewModel.exportSelected()
            } label: {
                Label("エクスポート", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(job.status != .succeeded)

            Spacer()
        }
        .padding(18)
        .frame(width: 320, height: 400)
    }
}

struct ItemDetailPopover: View {
    let item: ProjectItem
    @ObservedObject var viewModel: ImageCreatorViewModel
    @State private var isRevisedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailRow(label: "Prompt", value: item.prompt)
            DetailRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let revisedPrompt = item.revisedPrompt {
                DisclosureGroup(isExpanded: $isRevisedExpanded) {
                    DetailRow(label: "", value: revisedPrompt)
                        .padding(.top, 4)
                } label: {
                    Text("Revised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = item.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            Divider()
                .padding(.vertical, 2)

            Button {
                viewModel.edit(item: item)
                viewModel.selectedItemID = nil
            } label: {
                Label("再編集", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                viewModel.removeBackground(item: item)
                viewModel.selectedItemID = nil
            } label: {
                Label("背景を除去", systemImage: "scissors")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                viewModel.reveal(item: item)
            } label: {
                Label("Finderで表示", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button {
                viewModel.exportItem(item)
            } label: {
                Label("エクスポート", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .frame(width: 300, height: 380)
    }
}

private struct ErrorToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(5)
        }
    }
}

struct AccountPopover: View {
    let status: CodexAccountUsageStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("アカウント")
                .font(.headline)

            DetailRow(label: "種別", value: status.accountKind.japaneseLabel)

            if let email = status.accountEmail {
                DetailRow(label: "メール", value: email)
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 280, height: 140)
    }
}

// MARK: - Log Window

struct LogWindow: View {
    @ObservedObject var viewModel: ImageCreatorViewModel

    var body: some View {
        HSplitView {
            logPane(title: "App Log", lines: Array(viewModel.logs.suffix(240)))
                .frame(minWidth: 360)

            logPane(title: "Job Log", lines: viewModel.selectedJob?.logs ?? [])
                .frame(minWidth: 320)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 420)
    }

    private func logPane(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if lines.isEmpty {
                        Text("ログはまだありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Counter Control

private struct CounterControl: View {
    let systemImage: String
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let helpText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("\(label) \(value)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()

            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(helpText)
    }
}

// MARK: - Generating Indicator

private struct GenerationProgressView: View {
    let onStop: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isHovering {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Prompt Text View

private final class FocusableTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusableTextView()
        textView.font = NSFont.systemFont(ofSize: 18)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onFocusChange = { focused in
            context.coordinator.isFocused = focused
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: GenerationJobStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .queued: return .secondary
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .orange
        }
    }
}

// MARK: - Canvas Zoom Control

private struct CanvasZoomControl: View {
    @Binding var zoom: CGFloat
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0
    private let step: CGFloat = 0.1

    var body: some View {
        HStack(spacing: 8) {
            Button {
                zoom = max(minZoom, zoom - step)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(zoom <= minZoom)

            Slider(value: $zoom, in: minZoom...maxZoom)
                .frame(width: 140)

            Button {
                zoom = min(maxZoom, zoom + step)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(zoom >= maxZoom)

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { zoom = 1.0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}
