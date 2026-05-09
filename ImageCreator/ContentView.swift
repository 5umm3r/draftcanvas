import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLogWindowVisible = false
    @State private var editingProjectID: UUID?
    @State private var renamingText = ""
    @State private var confirmingDeleteProjectID: UUID?
    @State private var isAccountPopoverPresented = false
    @State private var promptIsFocused = false
    @State private var promptTextHeight: CGFloat = 76
    @State private var canvasZoom: CGFloat = 1.0
    @State private var enhanceRotation: Double = 0
    @State private var isPromptDropTargeted = false
    @State private var isCanvasDropTargeted = false
    @State private var dragDropTargetProjectID: UUID?
    @State private var dragDropItemID: UUID?
    @State private var isDroppingOnProject: [UUID: Bool] = [:]

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
    }

    // MARK: - Top Bar

    private var topStatusBar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.chooseSaveFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.body.weight(.semibold))
                    Text("保存先")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)
            .help("保存先フォルダ: \(viewModel.preferredSaveFolderLabel)")

            Button(action: toggleLogWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.body.weight(.semibold))
                    Text("ログ")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)

            Menu {
                Button {
                    viewModel.completionSound = CompletionSoundOption.off.rawValue
                } label: {
                    HStack {
                        Text(CompletionSoundOption.off.displayName)
                        if viewModel.completionSound == CompletionSoundOption.off.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(CompletionSoundOption.allCases.filter { $0 != .off }, id: \.self) { option in
                    Button {
                        viewModel.completionSound = option.rawValue
                        NSSound(named: NSSound.Name(option.rawValue))?.play()
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if viewModel.completionSound == option.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.completionSound == CompletionSoundOption.off.rawValue
                        ? "speaker.slash"
                        : "speaker.wave.2")
                        .font(.body.weight(.semibold))
                    Text("完了音")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("完了通知サウンド: \(CompletionSoundOption(rawValue: viewModel.completionSound)?.displayName ?? viewModel.completionSound)")

            Spacer(minLength: 16)

            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.totalGeneratedImages)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .help("全プロジェクト累計生成枚数")

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
                        .font(.body)
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
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isAccountPopoverPresented, arrowEdge: .bottom) {
                AccountPopover(
                    status: viewModel.accountUsageStatus,
                    isLoading: viewModel.isRefreshingAccountUsage,
                    hasFailed: viewModel.accountUsagePrewarmFailed,
                    isLoggingOut: viewModel.isLoggingOut,
                    onRetry: viewModel.refreshAccountUsage,
                    onLogout: viewModel.logout
                )
            }

            planBadge

            Divider()
                .frame(height: 20)

            Button {
                viewModel.cycleAppearance()
            } label: {
                Image(systemName: AppAppearance(rawValue: viewModel.appAppearanceRaw)?.systemImage ?? "sun.max")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("テーマ切替")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.regularMaterial)
    }

    private var planBadge: some View {
        Text(viewModel.accountUsageStatus.planLabel)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
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
                ForEach(viewModel.sortedProjects) { project in
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

    // MARK: - Canvas

    private enum CanvasCardLayout {
        static let baseSquareSide: CGFloat = 220
        static let maxWidthMultiplier: CGFloat = 4.0 / 3.0  // sqrt(16/9)
        static func size(for ratio: CGFloat, zoom: CGFloat) -> CGSize {
            let r = max(ratio, 0.01)
            let s = sqrt(r)
            return CGSize(width: baseSquareSide * s * zoom, height: baseSquareSide / s * zoom)
        }
    }

    private func cardSize(forItem item: ProjectItem) -> CGSize {
        let ratio = viewModel.cachedImage(for: item)?.pixelAspectRatio
            ?? item.aspectRatio.widthOverHeight
        return CanvasCardLayout.size(for: ratio, zoom: canvasZoom)
    }

    private func cardSize(forJob job: GenerationJob) -> CGSize {
        CanvasCardLayout.size(for: job.aspectRatio.widthOverHeight, zoom: canvasZoom)
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                canvas

                promptPanel(maxPromptHeight: geometry.size.height / 2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            .sheet(item: $viewModel.inpaintingTarget) { item in
                inpaintingEditorSheet(for: item)
            }
        }
    }

    @ViewBuilder
    private func inpaintingEditorSheet(for item: ProjectItem) -> some View {
        if let nsImage = viewModel.cachedImage(for: item) {
            InpaintingMaskEditorSheet(
                originalImage: nsImage,
                onComplete: { strokes in
                    viewModel.applyInpaintingMask(item: item, strokes: strokes)
                },
                onCancel: {
                    viewModel.inpaintingTarget = nil
                }
            )
        } else {
            Text("画像を読み込めませんでした")
                .padding(40)
        }
    }

    private var canvas: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

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
                        columns: [GridItem(
                            .adaptive(minimum: CanvasCardLayout.baseSquareSide * canvasZoom),
                            spacing: 28
                        )],
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
                .onDrop(of: [.image, .fileURL], isTargeted: $isCanvasDropTargeted) { providers in
                    handleCanvasDrop(providers)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if viewModel.projects.isEmpty == false {
                    Button {
                        viewModel.importImageToCanvas()
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .help("画像をインポート")
                }
                if !viewModel.projects.isEmpty && !canvasEntries.isEmpty {
                    CanvasZoomControl(zoom: $canvasZoom)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: isCanvasDropTargeted ? 3 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isCanvasDropTargeted) { providers in
            handleCanvasDrop(providers)
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
        let size = cardSize(forItem: item)
        return Button {
            viewModel.selectedItemID = (viewModel.selectedItemID == item.id) ? nil : item.id
            viewModel.selectedJobID = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    checkerboard
                    previewForItem(item)
                }
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let sourceID = item.editedFromItemID,
                       let sourceItem = viewModel.items.first(where: { $0.id == sourceID }),
                       let sourceImage = viewModel.cachedImage(for: sourceItem) {
                        let thumbSize = 36 * max(0.7, min(canvasZoom, 1.6))
                        Image(nsImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbSize, height: thumbSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
                            }
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: thumbSize * 0.32, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: thumbSize * 0.5, height: thumbSize * 0.5)
                                    .background(Circle().fill(Color.accentColor))
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                    .offset(x: -thumbSize * 0.15, y: -thumbSize * 0.15)
                            }
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                            .padding(.trailing, -thumbSize / 3)
                            .padding(.bottom, -thumbSize / 3)
                    }
                }
                .overlay {
                    if viewModel.currentInputs.editSource?.projectItemID == item.id {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            viewModel.selectedItemID == item.id ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: viewModel.selectedItemID == item.id ? 3 : 1
                        )
                }
                .overlay {
                    if viewModel.vectorizingItemIDs.contains(item.id) {
                        VectorizingOverlay {
                            viewModel.cancelVectorization(for: item)
                        }
                    }
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
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            Group {
                if let nsImage = viewModel.cachedImage(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.3))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func generationCard(_ job: GenerationJob) -> some View {
        let size = cardSize(forJob: job)
        return Button {
            viewModel.selectedJobID = (viewModel.selectedJobID == job.id) ? nil : job.id
            viewModel.selectedItemID = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    checkerboard
                    preview(for: job)
                }
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            viewModel.selectedJobID == job.id ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: viewModel.selectedJobID == job.id ? 3 : 1
                        )
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
        let lightColor: Color = colorScheme == .dark ? Color.white.opacity(0.18) : Color.white
        let darkColor: Color = colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
        return Canvas { context, size in
            let side: CGFloat = 18
            for x in stride(from: CGFloat(0), to: size.width, by: side) {
                for y in stride(from: CGFloat(0), to: size.height, by: side) {
                    let isDark = (Int(x / side) + Int(y / side)).isMultiple(of: 2)
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    context.fill(Path(rect), with: .color(isDark ? lightColor : darkColor))
                }
            }
        }
    }

    // MARK: - Prompt Panel

    private func promptPanel(maxPromptHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let editSource = viewModel.currentInputs.editSource {
                HStack(spacing: 8) {
                    Image(systemName: editSource.isInpainting ? "paintbrush.pointed" : "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Text(editSource.isInpainting ? "マスクして編集モード" : "再編集モード")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("解除") {
                        viewModel.cancelEditingHistoryItem()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background((editSource.isInpainting ? Color.orange : Color.accentColor).opacity(0.10))

                Divider()
            }

            if let attachedImage = viewModel.currentInputs.attachedImage {
                HStack {
                    AttachedImageThumbnail(
                        filePath: attachedImage.filePath,
                        onRemove: { viewModel.removeAttachedImage() }
                    )
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }

            let minH: CGFloat = 76
            let maxH = max(minH, maxPromptHeight)
            let clampedHeight = min(max(promptTextHeight, minH), maxH)
            ZStack(alignment: .bottomTrailing) {
                PromptTextView(
                    text: viewModel.binding(for: \.prompt),
                    isFocused: $promptIsFocused,
                    dynamicHeight: $promptTextHeight,
                    maxHeight: maxH,
                    onSubmit: viewModel.generate,
                    onSetupReplacer: { replacer in
                        viewModel.onReplacePromptText = replacer
                    },
                    onPasteImage: {
                        viewModel.pasteImageFromClipboard()
                    }
                )
                .frame(height: clampedHeight)
                .animation(.easeOut(duration: 0.12), value: clampedHeight)
                .overlay(alignment: .topLeading) {
                    if viewModel.currentInputs.prompt.isEmpty && !promptIsFocused {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                // ボタン(28pt) + 右padding(8pt) + gap(8pt) = 44pt 確保
                .padding(.trailing, 44)

                let promptEmpty = viewModel.currentInputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let enhanceDisabled = promptEmpty || viewModel.isEnhancingPrompt
                Button {
                    viewModel.enhancePrompt()
                } label: {
                    Group {
                        if viewModel.isEnhancingPrompt {
                            Image(systemName: "sparkle")
                                .rotationEffect(.degrees(enhanceRotation))
                                .onAppear {
                                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                        enhanceRotation = 360
                                    }
                                }
                                .onDisappear { enhanceRotation = 0 }
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(
                        viewModel.isEnhancingPrompt
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(0.06)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(enhanceDisabled)
                .opacity(enhanceDisabled && !viewModel.isEnhancingPrompt ? 0.3 : 1.0)
                .help("プロンプトをエンハンス (詳細化)")
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider()

            HStack(spacing: 16) {

                Menu {
                    ForEach(viewModel.availableModels) { model in
                        Button {
                            viewModel.binding(for: \.model).wrappedValue = model.id
                        } label: {
                            Label(model.displayName, systemImage: viewModel.currentInputs.model == model.id ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 13))
                        Text(modelShortName)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(viewModel.availableModels.isEmpty)
                .help("モデル選択")

                Menu {
                    let efforts = viewModel.availableModels
                        .first(where: { $0.id == viewModel.currentInputs.model })?
                        .supportedReasoningEfforts ?? ["low", "medium", "high"]
                    ForEach(efforts, id: \.self) { effort in
                        Button {
                            viewModel.binding(for: \.reasoningEffort).wrappedValue = effort
                        } label: {
                            Label(reasoningLabel(effort), systemImage: viewModel.currentInputs.reasoningEffort == effort ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "brain")
                            .font(.system(size: 13))
                        Text(reasoningShortName)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("思考力")

                Menu {
                    ForEach(GenerationAspectRatio.allCases) { ar in
                        let selected = viewModel.currentInputs.aspectRatio == ar
                        Button {
                            viewModel.binding(for: \.aspectRatio).wrappedValue = ar
                        } label: {
                            Label("\(ar.title) \(ar.value)", systemImage: selected ? "checkmark" : "")
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
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("アスペクト比")

                Menu {
                    ForEach(1...4, id: \.self) { n in
                        Button {
                            viewModel.binding(for: \.count).wrappedValue = n
                            if viewModel.currentInputs.concurrency > n {
                                viewModel.binding(for: \.concurrency).wrappedValue = n
                            }
                        } label: { Label("\(n)枚", systemImage: viewModel.currentInputs.count == n ? "checkmark" : "") }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 13))
                        Text("\(viewModel.currentInputs.count)枚")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("枚数")

                Menu {
                    ForEach(1...viewModel.currentInputs.count, id: \.self) { n in
                        Button { viewModel.binding(for: \.concurrency).wrappedValue = n } label: { Label("\(n)並列", systemImage: viewModel.currentInputs.concurrency == n ? "checkmark" : "") }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: 13))
                        Text("\(viewModel.currentInputs.concurrency)並列")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("並列実行数")

                Spacer()

                Button {
                    viewModel.pickAttachmentImage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 15, weight: .medium))
                        if viewModel.currentInputs.attachedImage != nil {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(viewModel.currentInputs.attachedImage != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.currentInputs.editSource != nil)
                .help(viewModel.currentInputs.attachedImage != nil ? "参照画像添付中" : "参照画像を添付")

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
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor, lineWidth: isPromptDropTargeted ? 2 : 0)
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isPromptDropTargeted) { providers in
            handlePromptDrop(providers)
        }
    }

    // MARK: - Drop Handlers

    private func handlePromptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let fileURL: URL?
                if let u = item as? URL { fileURL = u }
                else if let u = item as? NSURL { fileURL = u as URL }
                else if let data = item as? Data { fileURL = URL(dataRepresentation: data, relativeTo: nil) }
                else { fileURL = nil }
                guard let fileURL else { return }
                Task { @MainActor in self.viewModel.attachImage(from: fileURL) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage else { return }
                Task { @MainActor in self.viewModel.attachImageFromPasteboard(image) }
            }
            return true
        }
        return false
    }

    private func handleCanvasDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let fileURL: URL?
                    if let u = item as? URL { fileURL = u }
                    else if let u = item as? NSURL { fileURL = u as URL }
                    else if let data = item as? Data { fileURL = URL(dataRepresentation: data, relativeTo: nil) }
                    else { fileURL = nil }
                    guard let fileURL else { return }
                    Task { @MainActor in
                        let projectID = self.viewModel.selectedProjectID ?? self.viewModel.createProject().id
                        self.viewModel.importImageAsProjectItem(url: fileURL, projectID: projectID)
                    }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let image = obj as? NSImage else { return }
                    Task { @MainActor in
                        let projectID = self.viewModel.selectedProjectID ?? self.viewModel.createProject().id
                        self.viewModel.importImageAsProjectItem(image: image, projectID: projectID)
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func handleProjectDrop(_ providers: [NSItemProvider], targetProjectID: UUID) -> Bool {
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

    private var modelShortName: String {
        if let m = viewModel.availableModels.first(where: { $0.id == viewModel.currentInputs.model }) {
            return m.displayName
        }
        return viewModel.currentInputs.model.isEmpty ? "—" : viewModel.currentInputs.model
    }

    private var reasoningShortName: String {
        reasoningLabel(viewModel.currentInputs.reasoningEffort)
    }

    private func reasoningLabel(_ effort: String) -> String {
        switch effort {
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh": return "最高"
        default: return effort
        }
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
                .font(.body.weight(.semibold))
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
                    .fill(Color.primary.opacity(0.12))

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

            PopoverButton(systemImage: "square.and.arrow.down", title: "エクスポート") {
                viewModel.exportSelected()
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
    @State private var isConfirmingDelete = false

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

            PopoverButton(systemImage: "wand.and.stars", title: "再編集") {
                viewModel.edit(item: item)
                viewModel.selectedItemID = nil
            }

            PopoverButton(systemImage: "paintbrush.pointed", title: "マスクして編集") {
                viewModel.inpaint(item: item)
                viewModel.selectedItemID = nil
            }

            PopoverButton(
                systemImage: "scissors",
                title: "背景を除去",
                action: {
                    viewModel.removeBackground(item: item)
                    viewModel.selectedItemID = nil
                },
                isDisabled: item.isBackgroundRemoved,
                disabledReason: item.isBackgroundRemoved ? "背景除去済み" : nil
            )

            PopoverButton(
                systemImage: "pencil.and.outline",
                title: "ベクター化",
                action: {
                    viewModel.vectorize(item: item)
                    viewModel.selectedItemID = nil
                },
                isDisabled: item.hasSVG,
                disabledReason: item.hasSVG ? "ベクター化済み" : nil
            )

            PopoverButton(systemImage: "doc.on.doc", title: "複製") {
                viewModel.duplicateItem(item)
                viewModel.selectedItemID = nil
            }

            PopoverButton(systemImage: "folder", title: "Finderで表示") {
                viewModel.reveal(item: item)
            }

            PopoverButton(systemImage: "trash", title: "削除") {
                isConfirmingDelete = true
            }
            .foregroundStyle(.red)

            Divider()
                .padding(.vertical, 4)

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
        .frame(width: 300, height: 525)
        .alert("画像を削除しますか？", isPresented: $isConfirmingDelete) {
            Button("削除", role: .destructive) {
                viewModel.deleteItem(item)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
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
    let isLoading: Bool
    let hasFailed: Bool
    let isLoggingOut: Bool
    let onRetry: () -> Void
    let onLogout: () -> Void

    private var canLogout: Bool {
        status.accountKind == .chatgpt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("読み込み中...")
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if hasFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("取得に失敗しました")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button("再試行", action: onRetry)
                }
            } else {
                // ヘッダー
                HStack(spacing: 10) {
                    Image(systemName: status.accountKind.systemImageName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.accountLabel)
                            .font(.headline)
                            .lineLimit(1)
                        if status.planLabel != "-" {
                            Text(status.planLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                }

                // ログアウト
                if canLogout {
                    Divider().padding(.vertical, 10)
                    Button(action: onLogout) {
                        HStack(spacing: 6) {
                            if isLoggingOut {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text("ログアウト")
                        }
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoggingOut)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
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
                Group {
                    if lines.isEmpty {
                        Text("ログはまだありません。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .background(Color.primary.opacity(0.04))
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
        .background(Color.primary.opacity(0.04))
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

private struct VectorizingOverlay: View {
    let onCancel: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(isHovering ? 0.55 : 0.35))

            if isHovering {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.large)
                        .colorScheme(.dark)
                    Text("ベクター化中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Prompt Text View

private final class FocusableTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onFrameChange: (() -> Void)?
    var onPasteImage: (() -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameChange),
            name: NSView.frameDidChangeNotification,
            object: self
        )
    }

    @objc private func handleFrameChange() {
        onFrameChange?()
    }

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

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let isShiftHeld = event.modifierFlags.contains(.shift)
        if isReturn && !isShiftHeld && !hasMarkedText() {
            onSubmit?()
            return
        }
        // Cmd+V: クリップボードに画像のみある場合は画像添付
        let isCommandV = event.keyCode == 9 && event.modifierFlags.contains(.command)
        if isCommandV {
            let pb = NSPasteboard.general
            let hasText = pb.string(forType: .string) != nil
            let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
            if hasImage && !hasText {
                onPasteImage?()
                return
            }
        }
        super.keyDown(with: event)
    }
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var dynamicHeight: CGFloat
    var maxHeight: CGFloat
    var onSubmit: (() -> Void)?
    var onSetupReplacer: ((@escaping (String) -> Void) -> Void)?
    var onPasteImage: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusableTextView()
        textView.font = NSFont.systemFont(ofSize: 18)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onFocusChange = { focused in
            context.coordinator.isFocused = focused
        }
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.onSubmit?()
        }
        textView.onFrameChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.recalculateHeight(for: textView)
        }
        textView.onPasteImage = { [weak coordinator = context.coordinator] in
            coordinator?.onPasteImage?()
        }

        context.coordinator.textViewRef = textView
        onSetupReplacer?({ [weak coordinator = context.coordinator] newText in
            coordinator?.replaceTextUndoably(newText)
        })

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight(for: textView)
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onPasteImage = onPasteImage
        context.coordinator.maxHeight = maxHeight
        scrollView.hasVerticalScroller = dynamicHeight >= maxHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, dynamicHeight: $dynamicHeight, maxHeight: maxHeight, onSubmit: onSubmit, onPasteImage: onPasteImage)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var dynamicHeight: CGFloat
        var maxHeight: CGFloat
        var onSubmit: (() -> Void)?
        var onPasteImage: (() -> Void)?
        weak var textViewRef: FocusableTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>, dynamicHeight: Binding<CGFloat>, maxHeight: CGFloat, onSubmit: (() -> Void)?, onPasteImage: (() -> Void)?) {
            _text = text
            _isFocused = isFocused
            _dynamicHeight = dynamicHeight
            self.maxHeight = maxHeight
            self.onSubmit = onSubmit
            self.onPasteImage = onPasteImage
        }

        func replaceTextUndoably(_ newText: String) {
            guard let tv = textViewRef else { return }
            tv.selectAll(nil)
            tv.insertText(newText, replacementRange: tv.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            recalculateHeight(for: textView)
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)
            guard abs(newHeight - dynamicHeight) > 0.5 else { return }
            dynamicHeight = newHeight
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Helpers

private extension NSImage {
    var pixelAspectRatio: CGFloat? {
        guard let rep = representations.first(where: { $0 is NSBitmapImageRep })
                    ?? representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        return w / h
    }
}

// MARK: - Attached Image Thumbnail

private struct AttachedImageThumbnail: View {
    let filePath: String
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image = NSImage(contentsOfFile: filePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 80, maxHeight: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .background(Color(nsColor: .windowBackgroundColor).clipShape(Circle()))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }
}

// MARK: - Popover Button

struct PopoverButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var disabledReason: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(isDisabled)
        .help(disabledReason ?? "")
    }
}
