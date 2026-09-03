import SwiftUI
import os.signpost

extension ContentView {
    var canvasEntries: [CanvasEntry] { cachedCanvasEntries }

    var firstJobEntryID: UUID? {
        canvasEntries.first { if case .job = $0 { return true } else { return false } }?.id
    }

    func recomputeCanvasEntries() {
        let persistedItems = viewModel.displayedItemsSnapshot.map { CanvasEntry.item($0) }
        let showJobs = viewModel.isGeneratingForSelected && viewModel.selectedFilteringProjectID == nil && !viewModel.isSearchActive
        let inProgressJobs = showJobs ? viewModel.currentJobs.map { CanvasEntry.job($0) } : []
        let all = persistedItems + inProgressJobs
        switch viewModel.canvasSortOrder {
        case .createdAtAscending: cachedCanvasEntries = all.sorted { $0.sortDate < $1.sortDate }
        case .createdAtDescending: cachedCanvasEntries = all.sorted { $0.sortDate > $1.sortDate }
        }
    }

    @ViewBuilder
    func canvasCard(for entry: CanvasEntry) -> some View {
        switch entry {
        case .item(let item):
            itemCard(item)
        case .job(let job):
            generationCard(job)
        }
    }

    func itemCard(_ item: ProjectItem) -> some View {
        let size = cardSize(forItem: item)
        let isMultiSelected = viewModel.selectedItemIDs.contains(item.id)
        let isSingleSelected = viewModel.selectedItemID == item.id
        let isSelected = isMultiSelected || isSingleSelected
        return VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let sourceID = item.editedFromItemID,
                       let sourceItem = viewModel.itemsByID[sourceID] {
                        let thumbSize = 36 * max(0.7, min(canvasZoom, 1.6))
                        ItemThumbnailView(
                            thumbnailStore: viewModel.thumbnailStore,
                            item: sourceItem,
                            originalURL: viewModel.fileURL(for: sourceItem),
                            contentMode: .fill,
                            syncMonitor: viewModel.syncMonitor
                        )
                        .frame(width: thumbSize, height: thumbSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
                            }
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: thumbSize * 0.26, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: thumbSize * 0.38, height: thumbSize * 0.38)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .offset(x: -thumbSize * 0.1, y: -thumbSize * 0.1)
                            }
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                            .offset(x: thumbSize / 3, y: thumbSize / 3)
                            .zIndex(isSelected ? -1 : 1)
                    }
                    ItemCardPreview(
                        item: item,
                        size: size,
                        isSelected: isSelected,
                        isMultiSelected: isMultiSelected,
                        viewModel: viewModel
                    )
                }
            }
        .onTapGesture(count: 2) {
            expandedItem = item
        }
        .onTapGesture(count: 1) {
            if viewModel.isSelectionMode {
                viewModel.toggleMultiSelection(item)
            } else {
                if viewModel.selectedItemIDs.contains(item.id) && viewModel.selectedItemIDs.count > 1 {
                    return
                }
                viewModel.selectedItemID = item.id
                viewModel.selectedJobID = nil
            }
        }
        .rightClickPopover(
            onOpen: {
                viewModel.selectedItemID = item.id
                os_signpost(.begin, log: PopoverSignposter.log, name: "ItemDetailPopover")
            }
        ) {
            ItemDetailPopover(item: item, viewModel: viewModel)
        }
        .onDrag {
            let isBatch = viewModel.isSelectionMode
                && viewModel.selectedItemIDs.contains(item.id)
                && viewModel.selectedItemIDs.count > 1
            if isBatch {
                let payload = viewModel.items
                    .filter { viewModel.selectedItemIDs.contains($0.id) }
                    .map { $0.id.uuidString }
                    .joined(separator: "\n")
                return NSItemProvider(object: payload as NSString)
            } else {
                return NSItemProvider(object: item.id.uuidString as NSString)
            }
        } preview: {
            let isBatch = viewModel.isSelectionMode
                && viewModel.selectedItemIDs.contains(item.id)
                && viewModel.selectedItemIDs.count > 1
            if isBatch {
                let selected = viewModel.items.filter { viewModel.selectedItemIDs.contains($0.id) }
                MultiDragPreview(
                    items: Array(selected.prefix(3)),
                    total: selected.count,
                    viewModel: viewModel
                )
            } else {
                ItemThumbnailView(
                    thumbnailStore: viewModel.thumbnailStore,
                    item: item,
                    originalURL: viewModel.fileURL(for: item),
                    contentMode: .fit,
                    syncMonitor: viewModel.syncMonitor
                )
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    func generationCard(_ job: GenerationJob) -> some View {
        let size = cardSize(forJob: job)
        return Button {
            viewModel.selectedJobID = (viewModel.selectedJobID == job.id) ? nil : job.id
            viewModel.selectedItemID = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview(for: job)
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
                .environment(\.locale, l10n.locale)
        }
    }

    @ViewBuilder
    func previewForItem(_ item: ProjectItem) -> some View {
        ItemThumbnailView(
            thumbnailStore: viewModel.thumbnailStore,
            item: item,
            originalURL: viewModel.fileURL(for: item),
            contentMode: .fit,
            cardSize: cardSize(forItem: item),
            originalStore: viewModel.originalImageStore,
            syncMonitor: viewModel.syncMonitor,
            enableOriginalUpgrade: true
        )
    }

    @ViewBuilder
    func preview(for job: GenerationJob) -> some View {
        JobPreviewView(job: job)
    }

    var checkerboard: some View {
        CanvasCheckerboardView(isDark: colorScheme == .dark)
    }

    @ViewBuilder
    var canvasActionPanel: some View {
        if let selectedID = viewModel.selectedItemID, let item = viewModel.itemsByID[selectedID],
           !viewModel.isSelectionMode {
            VStack(spacing: 6) {
                VariationMenuButton(item: item, viewModel: viewModel)
                CircularPromptActionButton(
                    systemImage: "wand.and.stars",
                    tooltip: "再編集",
                    showCostBadge: viewModel.showCostBadge
                ) {
                    viewModel.edit(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "paintbrush.pointed",
                    tooltip: "マスク編集",
                    showCostBadge: viewModel.showCostBadge
                ) {
                    viewModel.openMaskEditor(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                    tooltip: "アウトペイント",
                    showCostBadge: viewModel.showCostBadge
                ) {
                    viewModel.openOutpaintEditor(for: item)
                }
                CircularPromptActionButton(
                    systemImage: "scissors",
                    tooltip: "背景を除去",
                    isDisabled: item.isBackgroundRemoved
                ) {
                    viewModel.startBackgroundRemoval(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "crop",
                    tooltip: "トリミング"
                ) {
                    viewModel.openCropEditor(for: item)
                }
                CircularPromptActionButton(
                    systemImage: "pointer.arrow.and.square.on.square.dashed",
                    tooltip: "素材を抽出"
                ) {
                    viewModel.startMaterialExtraction(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "arrow.down.left.and.arrow.up.right.rectangle",
                    tooltip: "高解像度化",
                    isDisabled: viewModel.upscalingItemIDs.contains(item.id)
                ) {
                    viewModel.upscaleItem(item)
                }
                CircularPromptActionButton(
                    systemImage: "pencil.and.outline",
                    tooltip: "ベクター化",
                    isDisabled: item.hasSVG
                ) {
                    viewModel.vectorize(item: item)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 28, height: 1)
                    .padding(.vertical, 2)

                CircularPromptActionButton(
                    systemImage: item.isBookmarked ? "bookmark.fill" : "bookmark",
                    tooltip: item.isBookmarked ? "ブックマークを解除" : "ブックマーク",
                    isAccent: item.isBookmarked,
                    accentTint: .bookmarkTint
                ) {
                    viewModel.toggleBookmark(item)
                }

                ImageCopyButton(item: item, viewModel: viewModel)

                CircularPromptActionButton(
                    systemImage: "plus.square.on.square",
                    tooltip: "複製"
                ) {
                    viewModel.duplicateItem(item)
                }
                CircularPromptActionButton(
                    systemImage: "trash",
                    tooltip: viewModel.canDeleteItem(item) ? "削除" : "ブックマーク中は削除できません",
                    isDisabled: !viewModel.canDeleteItem(item),
                    isDestructive: true
                ) {
                    confirmingDeleteItemID = item.id
                }
                CircularShareButton(urls: [viewModel.fileURL(for: item)])
                CircularPromptActionButton(
                    systemImage: "square.and.arrow.up",
                    tooltip: "エクスポート",
                    isAccent: true
                ) {
                    viewModel.exportItem(item)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 2, y: 4)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }
}

/// アイテムカードのプレビュー領域。
/// ホバー状態をカード単位で保持するため、専用のViewとして切り出している。
private struct ItemCardPreview: View {
    let item: ProjectItem
    let size: CGSize
    let isSelected: Bool
    let isMultiSelected: Bool
    @ObservedObject var viewModel: DraftCanvasViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            CanvasCheckerboardView(isDark: colorScheme == .dark)
            ItemThumbnailView(
                thumbnailStore: viewModel.thumbnailStore,
                item: item,
                originalURL: viewModel.fileURL(for: item),
                contentMode: .fit,
                cardSize: size,
                originalStore: viewModel.originalImageStore,
                syncMonitor: viewModel.syncMonitor,
                enableOriginalUpgrade: true
            )
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if viewModel.currentInputs.editSource?.projectItemID == item.id {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                    lineWidth: isSelected ? 3 : 1
                )
        }
        .overlay(alignment: .topLeading) {
            if viewModel.isSelectionMode {
                Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isMultiSelected ? Color.accentColor : Color.primary.opacity(0.4))
                    .background(Circle().fill(.white).padding(2))
                    .padding(6)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if item.hasSVG && !viewModel.vectorizingItemIDs.contains(item.id) {
                Text("SVG")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.45), in: Capsule())
                    .padding(6)
            }
        }
        .overlay {
            if viewModel.vectorizingItemIDs.contains(item.id) {
                VectorizingOverlay {
                    viewModel.cancelVectorization(for: item)
                }
            } else if viewModel.upscalingItemIDs.contains(item.id) {
                VectorizingOverlay(label: "高解像度化中") {
                    viewModel.cancelUpscale(itemID: item.id)
                }
            } else if viewModel.extractingItemID == item.id {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                        Text("素材を解析中…")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isSelectionMode {
                // 選択モード中は表示のみ（トグル不可）。一括削除で保護される画像を視認できるようにする。
                if item.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(Color.bookmarkTint, in: Circle())
                        .padding(6)
                }
            } else if item.isBookmarked || isHovered {
                Button {
                    // 実際のトグルは highPriorityGesture 側で処理する。
                    // 祖先の onTapGesture / onDrag より確実に優先させるため。
                } label: {
                    Image(systemName: item.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isBookmarked ? Color.white : Color.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(item.isBookmarked ? Color.bookmarkTint : Color.primary.opacity(0.45), in: Circle())
                        .padding(6)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.toggleBookmark(item)
                        }
                    }
                )
                .help(item.isBookmarked ? "ブックマークを解除" : "ブックマーク")
            }
        }
        .onHover { isHovered = $0 }
    }
}

struct ImageCopyButton: View {
    let item: ProjectItem
    let viewModel: DraftCanvasViewModel
    @State private var didCopy = false

    var body: some View {
        CircularPromptActionButton(
            systemImage: didCopy ? "checkmark" : "doc.on.doc.fill",
            tooltip: didCopy ? "コピー完了" : "クリップボードにコピー"
        ) {
            Task {
                guard await viewModel.copyItemToClipboard(item) else { return }
                withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeIn(duration: 0.2)) { didCopy = false }
                }
            }
        }
    }
}

private struct VariationMenuButton: View {
    let item: ProjectItem
    let viewModel: DraftCanvasViewModel
    @State private var isHovered = false
    @State private var showPopover = false
    @State private var variationCount: Int = 4

    private let minCount = 1
    private let maxCount = 12

    private var isDisabled: Bool {
        item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.primary.opacity(isHovered ? 0.12 : 0.06),
                        in: Circle()
                    )
                if viewModel.showCostBadge {
                    CodexCostBadge()
                        .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .overlay(alignment: .leading) {
            if isHovered && !showPopover {
                Text(LocalizedStringKey("バリエーション"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .fixedSize()
                    .offset(x: 44)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .zIndex(isHovered ? 100 : 0)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(spacing: 6) {
                Stepper(value: $variationCount, in: minCount...maxCount) {
                    HStack(spacing: 2) {
                        Text("\(variationCount)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                        Text(LocalizedStringKey("枚"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.small)
                Button {
                    viewModel.generateVariations(item: item, count: variationCount)
                    showPopover = false
                } label: {
                    Text(LocalizedStringKey("生成"))
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)
            .frame(width: 130)
        }
    }
}

