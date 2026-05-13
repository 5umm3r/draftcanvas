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

extension ContentView {
    func promptPanel(maxPromptHeight: CGFloat) -> some View {
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

            let isCompact = !promptIsFocused && viewModel.currentInputs.prompt.isEmpty
            let minH: CGFloat = isCompact ? 28 : 76
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
                    }
                )
                .frame(height: clampedHeight)
                .animation(.easeInOut(duration: 0.2), value: clampedHeight)
                .overlay(alignment: .topLeading) {
                    if viewModel.currentInputs.prompt.isEmpty && !promptIsFocused {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
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
                            if let r = model.rating {
                                Label(
                                    "\(model.displayName)   コスト:\(r.cost)  賢さ:\(r.smart)  速さ:\(r.speed)",
                                    systemImage: viewModel.currentInputs.model == model.id ? "checkmark" : ""
                                )
                            } else {
                                Label(model.displayName, systemImage: viewModel.currentInputs.model == model.id ? "checkmark" : "")
                            }
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
        guard viewModel.selectedFilteringProjectID == nil else { return false }

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
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
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
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh": return "最高"
        default: return effort
        }
    }
}
