import SwiftUI
import UniformTypeIdentifiers

// loadItem コールバックで URL を収集し、全件揃ったら一括インポートするためのヘルパー
private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [(index: Int, url: URL)] = []
    private var remaining: Int

    init(count: Int) { remaining = count }

    func add(url: URL, index: Int) -> [URL]? {
        lock.withLock {
            urls.append((index: index, url: url))
            remaining -= 1
            return remaining == 0 ? urls.sorted { $0.index < $1.index }.map(\.url) : nil
        }
    }

    func skip() -> [URL]? {
        lock.withLock {
            remaining -= 1
            return remaining == 0 ? urls.sorted { $0.index < $1.index }.map(\.url) : nil
        }
    }
}

enum PromptPanelLayout {
    static func minHeight(isEmptyIdle: Bool, isCollapsed: Bool) -> CGFloat {
        isEmptyIdle ? 28 : (isCollapsed ? 32 : 76)
    }

    static func maxHeight(maxPromptHeight: CGFloat, minHeight: CGFloat, isCollapsed: Bool) -> CGFloat {
        if isCollapsed {
            return 32
        }

        let safeMaxPromptHeight = maxPromptHeight.isFinite && maxPromptHeight > 0
            ? maxPromptHeight
            : minHeight
        return max(minHeight, safeMaxPromptHeight)
    }

    static func clampedHeight(
        promptTextHeight: CGFloat,
        maxPromptHeight: CGFloat,
        isEmptyIdle: Bool,
        isCollapsed: Bool
    ) -> CGFloat {
        let minHeight = minHeight(isEmptyIdle: isEmptyIdle, isCollapsed: isCollapsed)
        let maxHeight = maxHeight(
            maxPromptHeight: maxPromptHeight,
            minHeight: minHeight,
            isCollapsed: isCollapsed
        )
        let safePromptTextHeight = promptTextHeight.isFinite && promptTextHeight > 0
            ? promptTextHeight
            : minHeight
        return min(max(safePromptTextHeight, minHeight), maxHeight)
    }
}

extension ContentView {
    func promptPanel(maxPromptHeight: CGFloat) -> some View {
        let prompt = viewModel.currentInputs.prompt
        let hasText = !prompt.isEmpty
        let isEmptyIdle = false
        let isCollapsed = !promptIsFocused && hasText && !isPromptHoverExpanded
            && !viewModel.isTemplatePopoverPresented && !viewModel.isHistoryPopoverPresented

        let minH = PromptPanelLayout.minHeight(isEmptyIdle: isEmptyIdle, isCollapsed: isCollapsed)
        let maxH = PromptPanelLayout.maxHeight(
            maxPromptHeight: maxPromptHeight,
            minHeight: minH,
            isCollapsed: isCollapsed
        )
        let clampedHeight = PromptPanelLayout.clampedHeight(
            promptTextHeight: promptTextHeight,
            maxPromptHeight: maxPromptHeight,
            isEmptyIdle: isEmptyIdle,
            isCollapsed: isCollapsed
        )

        return VStack(spacing: 0) {
            if !isCollapsed, let editSource = viewModel.currentInputs.editSource {
                HStack(spacing: 8) {
                    Image(systemName: editSource.isOutpainting
                          ? "arrow.up.and.down.and.arrow.left.and.right"
                          : editSource.isInpainting ? "paintbrush.pointed" : "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Text(editSource.isOutpainting
                         ? LocalizedStringKey("アウトペイント拡張モード")
                         : editSource.isInpainting ? LocalizedStringKey("マスクして編集モード") : LocalizedStringKey("再編集モード"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("解除") {
                        viewModel.cancelEditingHistoryItem()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background((editSource.isOutpainting ? Color.teal : editSource.isInpainting ? Color.orange : Color.accentColor).opacity(0.10))

                Divider()
            }

            if !isCollapsed, viewModel.accountUsageStatus.isChatGPTFreePlan {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(String(localized: "ChatGPT Free プランでは画像生成を利用できません"))
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                Divider()
            }

            if !isCollapsed, let attachedImage = viewModel.currentInputs.attachedImage {
                HStack {
                    AttachedImageThumbnail(
                        filePath: attachedImage.filePath,
                        overlayPath: viewModel.currentInputs.editSource.flatMap { src in
                            guard src.isInpainting, !src.isOutpainting else { return nil }
                            return viewModel.inpaintPreviewPath(for: src.projectItemID)
                        },
                        onTap: {
                            if attachedImage.kind == .sketch {
                                viewModel.openSketchEditorForReedit(attachedImage)
                                return
                            }
                            guard let editSource = viewModel.currentInputs.editSource,
                                  editSource.isInpainting,
                                  let item = viewModel.items.first(where: { $0.id == editSource.projectItemID })
                            else { return }
                            if editSource.isOutpainting {
                                let cached = viewModel.outpaintInsetsCache[item.id] ?? .zero
                                viewModel.openOutpaintEditor(for: item, initialInsets: cached)
                            } else {
                                viewModel.openMaskEditor(item: item)
                            }
                        },
                        onRemove: {
                            if viewModel.currentInputs.editSource != nil {
                                viewModel.cancelEditingHistoryItem()
                            } else {
                                viewModel.removeAttachedImage()
                            }
                        }
                    )
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }

            if !isCollapsed {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isHistoryPopoverPresented = false
                            viewModel.isTemplatePopoverPresented.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 11))
                            Text("テンプレート")
                                .font(.system(size: 12))
                        }
                        .frame(height: 24)
                        .padding(.horizontal, 8)
                        .background(viewModel.isTemplatePopoverPresented ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("テンプレート")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isTemplatePopoverPresented = false
                            viewModel.isHistoryPopoverPresented.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                            Text("生成履歴")
                                .font(.system(size: 12))
                        }
                        .frame(height: 24)
                        .padding(.horizontal, 8)
                        .background(viewModel.isHistoryPopoverPresented ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("生成履歴")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            ZStack(alignment: .bottomTrailing) {
                PromptTextView(
                    text: viewModel.binding(for: \.prompt),
                    isFocused: $promptIsFocused,
                    dynamicHeight: $promptTextHeight,
                    maxHeight: maxH,
                    onSubmit: { viewModel.generate() },
                    onSetupReplacer: { replacer in
                        viewModel.onReplacePromptText = replacer
                    },
                    onSetupAppender: { appender in
                        viewModel.onAppendPromptText = appender
                    },
                    onPasteImage: {
                        viewModel.pasteImageFromClipboard()
                    },
                    onDropFileURL: { url in
                        viewModel.attachImage(from: url)
                    },
                    onDropNSImage: { image in
                        viewModel.attachImageFromPasteboard(image)
                    },
                    onDragEntered: {
                        isPromptDropTargeted = true
                    },
                    onDragExited: {
                        isPromptDropTargeted = false
                    },
                    focusTrigger: $promptFocusTrigger
                )
                .frame(height: clampedHeight)
                .animation(.easeInOut(duration: 0.2), value: clampedHeight)
                .opacity(isCollapsed ? 0 : 1)
                .allowsHitTesting(!isCollapsed)
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty && !promptIsFocused && !isCollapsed {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .padding(.top, 0)
                    }
                }
                .padding(.trailing, isCollapsed ? 0 : 44)

                if !isCollapsed {
                    let promptEmpty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let enhanceDisabled = promptEmpty || viewModel.isEnhancingPrompt
                    Button {
                        guard EntitlementGate.shared.requireUnlocked() else { return }
                        viewModel.enhancePrompt()
                    } label: {
                        HStack(spacing: 3) {
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
                        }
                        .frame(minWidth: 28, minHeight: 28, maxHeight: 28)
                        .padding(.horizontal, viewModel.showCostBadge ? 4 : 0)
                        .background(
                            viewModel.isEnhancingPrompt
                                ? Color.accentColor.opacity(0.15)
                                : Color.primary.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .opacity(viewModel.showCostBadge ? 1 : 0)
                            .offset(x: 3, y: 3)
                    }
                    .disabled(enhanceDisabled)
                    .opacity(enhanceDisabled && !viewModel.isEnhancingPrompt ? 0.3 : 1.0)
                    .help("プロンプトをエンハンス (詳細化)")
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                }

                if isCollapsed {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            if let attached = viewModel.currentInputs.attachedImage {
                                Image(systemName: attached.kind == .sketch ? "scribble.variable" : "paperclip")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if viewModel.currentInputs.editSource != nil {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(prompt)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: clampedHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptFocusTrigger = true
                    }
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 16)
            .padding(.top, isCollapsed ? 0 : 6)

            if !isCollapsed {
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
                                Label(ar == .auto ? ar.title : "\(ar.title) \(ar.value)", systemImage: selected ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 13))
                            Text(viewModel.currentInputs.aspectRatio.displayLabel)
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
                        ForEach(1...8, id: \.self) { n in
                            Button {
                                viewModel.binding(for: \.count).wrappedValue = n
                                viewModel.binding(for: \.concurrency).wrappedValue = n
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

                    Toggle(isOn: $viewModel.translateToEnglish) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 13))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(String(localized: "英語正規化: 生成前に英語へ変換しブレを抑制。トークン消費が増えます。"))

                    Spacer()

                    Button {
                        viewModel.openSketchEditor()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scribble.variable")
                                .font(.system(size: 15, weight: .medium))
                            if viewModel.currentInputs.attachedImage?.kind == .sketch {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 42, height: 42)
                        .background(viewModel.currentInputs.attachedImage?.kind == .sketch ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.currentInputs.editSource != nil)
                    .help(LocalizedStringKey("ラフを描いて構図を指示"))

                    Button {
                        viewModel.pickAttachmentImage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 15, weight: .medium))
                            if viewModel.currentInputs.attachedImage?.kind == .regular {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 42, height: 42)
                        .background(viewModel.currentInputs.attachedImage?.kind == .regular ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.currentInputs.editSource != nil)
                    .help(viewModel.currentInputs.attachedImage?.kind == .regular ? LocalizedStringKey("参照画像添付中") : LocalizedStringKey("参照画像を添付"))

                    Button {
                        viewModel.generate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .offset(x: 3, y: 3)
                    }
                    .disabled(!viewModel.canGenerate || viewModel.isEditSourceGenerating)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
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
        .onHover { hovering in
            if hovering {
                hoverCollapseTask?.cancel()
                hoverCollapseTask = nil
                hoverExpandTask?.cancel()
                hoverExpandTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPromptHoverExpanded = true
                    }
                }
            } else {
                hoverExpandTask?.cancel()
                hoverExpandTask = nil
                hoverCollapseTask?.cancel()
                hoverCollapseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPromptHoverExpanded = false
                    }
                }
            }
        }
        .onChange(of: promptIsFocused) { _, newFocused in
            if !newFocused {
                hoverExpandTask?.cancel()
                hoverExpandTask = nil
                hoverCollapseTask?.cancel()
                hoverCollapseTask = nil
                isPromptHoverExpanded = false
            }
        }
        .onChange(of: viewModel.shouldFocusPromptAfterApply) { _, shouldFocus in
            if shouldFocus {
                viewModel.shouldFocusPromptAfterApply = false
                promptIsFocused = true
                promptFocusTrigger = true
            }
        }
    }

    func handlePromptDrop(_ providers: [NSItemProvider]) -> Bool {
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

    func handleCanvasDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        guard viewModel.selectedFilteringProjectID == nil && !viewModel.isSearchActive else { return false }

        let hasURLs = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        let hasImages = providers.contains { $0.canLoadObject(ofClass: NSImage.self) }
        guard hasURLs || hasImages else { return false }

        let projectID = viewModel.selectedProjectID ?? viewModel.createProject().id

        let urlProviderCount = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }.count

        if urlProviderCount > 0 {
            let accumulator = URLAccumulator(count: urlProviderCount)
            for (i, provider) in providers.enumerated() {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                    guard error == nil else {
                        _ = accumulator.skip()
                        return
                    }
                    let fileURL: URL?
                    if let u = item as? URL { fileURL = u }
                    else if let u = item as? NSURL { fileURL = u as URL }
                    else if let data = item as? Data { fileURL = URL(dataRepresentation: data, relativeTo: nil) }
                    else { fileURL = nil }

                    let ready: [URL]?
                    if let url = fileURL { ready = accumulator.add(url: url, index: i) }
                    else { ready = accumulator.skip() }

                    if let urls = ready {
                        Task { @MainActor in
                            self.viewModel.importImagesAsProjectItems(urls: urls, projectID: projectID)
                        }
                    }
                }
            }
        }

        // NSImage直接ドロップ: 個別処理（URL変換不可の場合、別PR対象）
        for provider in providers where provider.canLoadObject(ofClass: NSImage.self)
            && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage else { return }
                Task { @MainActor in
                    self.viewModel.importImageAsProjectItem(image: image, projectID: projectID)
                }
            }
        }

        return true
    }

    var modelShortName: String {
        if let m = viewModel.availableModels.first(where: { $0.id == viewModel.currentInputs.model }) {
            return m.displayName
        }
        return viewModel.currentInputs.model.isEmpty ? "—" : viewModel.currentInputs.model
    }

    var reasoningShortName: String {
        reasoningLabel(viewModel.currentInputs.reasoningEffort)
    }

    func reasoningLabel(_ effort: String) -> String {
        switch effort {
        case "low": return String(localized: "低")
        case "medium": return String(localized: "中")
        case "high": return String(localized: "高")
        case "xhigh": return String(localized: "最高")
        default: return effort
        }
    }

    @ViewBuilder
    var retryFailedJobsButton: some View {
        let failedJobs = viewModel.currentJobs.filter {
            $0.status == .failed && !viewModel.dismissedFailedJobIDs.contains($0.id)
        }
        if !failedJobs.isEmpty,
           !viewModel.isGeneratingForSelected,
           let projectID = viewModel.effectiveProjectID,
           viewModel.lastRequestByProject[projectID] != nil {
            HStack(spacing: 4) {
                Button {
                    viewModel.retryFailedJobs(projectID: projectID)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                        Text(String(localized: "失敗のみ再試行 (\(failedJobs.count))"))
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .help(String(localized: "失敗したジョブのみ再試行"))

                Button {
                    let ids = viewModel.currentJobs
                        .filter { $0.status == .failed }
                        .map(\.id)
                    viewModel.dismissedFailedJobIDs.formUnion(ids)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "閉じる"))
            }
        }
    }

}
