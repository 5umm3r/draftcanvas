import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isLogWindowVisible = false
    @State private var editingProjectID: UUID?
    @State private var renamingText = ""
    @State private var confirmingDeleteProjectID: UUID?

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
            // Action buttons (moved from left rail)
            Button(action: viewModel.chooseSaveFolder) {
                Label("保存先", systemImage: "folder")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("保存先フォルダ: \(viewModel.preferredSaveFolderLabel)")

            Button(action: toggleLogWindow) {
                Label("ログ", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Button(action: viewModel.stopServer) {
                Label("停止", systemImage: "stop.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 22)

            // Codex account section
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Codex")
                    .font(.subheadline.weight(.semibold))
            }

            Divider()
                .frame(height: 22)

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)

                Text(viewModel.accountUsageStatus.accountLabel)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .leading)

                Text(viewModel.accountUsageStatus.planLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 16)

            usagePill(
                systemName: "clock",
                label: viewModel.accountUsageStatus.primaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.primaryUsageRemainingFraction
            )
            usagePill(
                systemName: "calendar",
                label: viewModel.accountUsageStatus.secondaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.secondaryUsageRemainingFraction
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
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .help("Codexのアカウントと使用量を更新")
            .disabled(viewModel.isRefreshingAccountUsage)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.white.opacity(0.86))
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
                        renamingText: $renamingText,
                        onCommitRename: {
                            viewModel.renameProject(id: project.id, to: renamingText)
                            editingProjectID = nil
                        },
                        onCancelRename: {
                            editingProjectID = nil
                        }
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
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            renamingText = project.name
                            editingProjectID = project.id
                        }
                    )
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
                ScrollView([.vertical, .horizontal]) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(220), spacing: 28), count: 3),
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
    }

    private var canvasEntries: [CanvasEntry] {
        let persistedItems = viewModel.itemsForSelectedProject.map { CanvasEntry.item($0) }
        let inProgressJobs = viewModel.isGenerating ? viewModel.jobs.map { CanvasEntry.job($0) } : []
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
                .frame(width: 220, height: 220)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    Text(item.outputMode.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14))
                        .foregroundStyle(Color.green)
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
                .frame(width: 220, height: 220)
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
        let fileURL = viewModel.fileURL(for: item)
        if item.outputMode == .raster, let nsImage = NSImage(contentsOf: fileURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else if let svgText = try? String(contentsOf: fileURL, encoding: .utf8) {
            svgPreview(svgText)
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
                .padding(10)
        } else if let svgText = job.svgText {
            svgPreview(svgText)
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
            ProgressView()
                .controlSize(.large)
        }
    }

    private func svgPreview(_ svgText: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "curlybraces.square")
                .font(.system(size: 34))
            Text(svgText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
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
            if viewModel.isEditingHistoryItem {
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

            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 18))
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .overlay(alignment: .topLeading) {
                    if viewModel.prompt.isEmpty {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 21)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            HStack(spacing: 14) {
                Picker("形式", selection: $viewModel.outputMode) {
                    ForEach(GenerationOutputMode.allCases) { mode in
                        Text(promptPanelModeTitle(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Picker("比率", selection: $viewModel.aspectRatio) {
                    ForEach(GenerationAspectRatio.allCases) { aspectRatio in
                        Text(promptPanelAspectRatioTitle(for: aspectRatio)).tag(aspectRatio)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 126)

                Toggle("背景を透過", isOn: $viewModel.transparentBackground)
                    .toggleStyle(.checkbox)

                Stepper("枚数 \(viewModel.count)", value: $viewModel.count, in: 1...24)
                    .frame(width: 115)

                Stepper("並列 \(viewModel.concurrency)", value: $viewModel.concurrency, in: 1...8)
                    .frame(width: 135)

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

    private func promptPanelModeTitle(for mode: GenerationOutputMode) -> String {
        switch mode {
        case .raster: return "画像"
        case .svg: return "SVG"
        }
    }

    private func promptPanelAspectRatioTitle(for aspectRatio: GenerationAspectRatio) -> String {
        "\(aspectRatio.title) \(aspectRatio.value)"
    }

    private func usagePill(systemName: String, label: String, remainingFraction: Double?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()

            usageProgressBar(value: remainingFraction)
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
    @Binding var renamingText: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    var body: some View {
        if isEditing {
            TextField("プロジェクト名", text: $renamingText, onCommit: onCommitRename)
                .textFieldStyle(.plain)
                .onExitCommand { onCancelRename() }
        } else {
            Text(project.name)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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
            DetailRow(label: "Mode", value: job.svgText == nil ? "PNG" : "SVG")
            DetailRow(label: "Prompt", value: job.prompt)

            if let revisedPrompt = job.revisedPrompt {
                DetailRow(label: "Revised", value: revisedPrompt)
            }
            if let errorMessage = job.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            Divider()

            Button {
                viewModel.saveSelected()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("詳細")
                .font(.headline)

            DetailRow(label: "Mode", value: item.outputMode.title)
            DetailRow(label: "Prompt", value: item.prompt)
            DetailRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let revisedPrompt = item.revisedPrompt {
                DetailRow(label: "Revised", value: revisedPrompt)
            }
            if let errorMessage = item.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            Divider()

            Button {
                viewModel.edit(item: item)
                viewModel.selectedItemID = nil
            } label: {
                Label("再編集", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                viewModel.saveItem(item)
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                viewModel.reveal(item: item)
            } label: {
                Label("Finderで表示", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 320, height: 420)
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
