import SwiftUI
import os.signpost

enum CanvasEntry: Identifiable {
    case item(ProjectItem)
    case job(GenerationJob)

    var id: UUID {
        switch self {
        case .item(let i): return i.id
        case .job(let j): return j.id
        }
    }

    var itemID: UUID? {
        if case .item(let item) = self { return item.id }
        return nil
    }
}

enum CanvasCardLayout {
    static let baseSquareSide: CGFloat = 220
    static let baseSpacing: CGFloat = 20
    static let minSpacing: CGFloat = 8

    static func size(for ratio: CGFloat, zoom: CGFloat) -> CGSize {
        let r = max(ratio, 0.01)
        let longSide = baseSquareSide * zoom
        if r >= 1 {
            return CGSize(width: longSide, height: longSide / r)
        } else {
            return CGSize(width: longSide * r, height: longSide)
        }
    }

    static func spacing(zoom: CGFloat) -> CGFloat {
        max(minSpacing, baseSpacing * zoom)
    }
}

extension ContentView {
    func cardSize(forItem item: ProjectItem) -> CGSize {
        let ratio = item.actualAspectRatio ?? item.aspectRatio.widthOverHeight
        return CanvasCardLayout.size(for: ratio, zoom: canvasZoom)
    }

    func cardSize(forJob job: GenerationJob) -> CGSize {
        CanvasCardLayout.size(for: job.aspectRatio.widthOverHeight, zoom: canvasZoom)
    }

    var canvasArea: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                canvas

                promptPanel(maxPromptHeight: geometry.size.height / 2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                VStack(spacing: 8) {
                    if let errorMessage = viewModel.importError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                            Text(errorMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                            Button {
                                viewModel.importError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if let progress = viewModel.batchExportProgress {
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text(L("\(progress.done) / \(progress.total) 枚処理中…"))
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.2), value: viewModel.batchExportProgress != nil)
                .animation(.easeInOut(duration: 0.2), value: viewModel.importProgress != nil)
                .animation(.easeInOut(duration: 0.2), value: viewModel.importError != nil)
            }
            .overlay(alignment: .leading) {
                canvasActionPanel
                    .padding(.leading, 16)
            }
            .animation(.easeInOut(duration: 0.1), value: viewModel.selectedItemID)
            .sheet(item: $viewModel.inpaintingTarget) { item in
                inpaintingEditorSheet(for: item)
                    .environment(\.locale, l10n.locale)
            }
            .sheet(item: $viewModel.backgroundRemovalPreview) { preview in
                BackgroundRemovalPreviewSheet(preview: preview, viewModel: viewModel)
                    .environment(\.locale, l10n.locale)
            }
            .sheet(item: $viewModel.materialExtractionPreview) { preview in
                MaterialExtractionSheet(preview: preview, viewModel: viewModel)
                    .environment(\.locale, l10n.locale)
            }
            .sheet(item: $viewModel.upscalePreview) { payload in
                UpscalePreviewSheet(payload: payload) { mode in
                    viewModel.commitUpscale(payload: payload, mode: mode)
                }
                .environment(\.locale, l10n.locale)
            }
            .onAppear {
                #if DEBUG
                CanvasMetrics.reset()
                viewModel.appendLog(CanvasMetrics.logSummary(tag: "appear"))
                #endif
            }
            .onDisappear {
                #if DEBUG
                viewModel.appendLog(CanvasMetrics.logSummary(tag: "disappear"))
                #endif
            }
        }
    }

    @ViewBuilder
    func inpaintingEditorSheet(for item: ProjectItem) -> some View {
        if let nsImage = viewModel.cachedImage(for: item) {
            InpaintingMaskEditorSheet(
                originalImage: nsImage,
                mode: $viewModel.inpaintMode,
                initialStrokes: viewModel.projectStore.readStrokesData(id: item.id) ?? [],
                onComplete: { strokes in
                    if viewModel.inpaintMode == .remove {
                        viewModel.applyMaskRemoval(item: item, strokes: strokes)
                    } else {
                        viewModel.applyInpaintingMask(item: item, strokes: strokes)
                    }
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

    var canvas: some View {
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
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        let gridSpacing = CanvasCardLayout.spacing(zoom: canvasZoom)
                        LazyVGrid(
                            columns: [GridItem(
                                .adaptive(minimum: CanvasCardLayout.baseSquareSide * canvasZoom),
                                spacing: gridSpacing
                            )],
                            spacing: gridSpacing
                        ) {
                            ForEach(canvasEntries) { entry in
                                canvasCard(for: entry)
                                    .id(entry.id)
                                    .background(
                                        Group {
                                            if let itemID = entry.itemID {
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: CardFramePreferenceKey.self,
                                                        value: [itemID: geo.frame(in: .named("canvasViewport"))]
                                                    )
                                                }
                                            }
                                        }
                                    )
                            }
                        }
                        .padding(.top, 72)
                        .padding(.leading, 84)
                        .padding(.trailing, 24)
                        .padding(.bottom, 220)
                        .background(
                            AutoScrollerAnchor(scroller: canvasAutoScroller)
                                .allowsHitTesting(false)
                        )
                    }
                    .coordinateSpace(name: "canvasViewport")
                    .onTapGesture {
                        viewModel.selectedItemID = nil
                        viewModel.selectedJobID = nil
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear { canvasViewportHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in canvasViewportHeight = h }
                        }
                    )
                    .overlay(
                        CanvasScrollZoomCatcher { delta in
                            let newZoom = canvasZoom * CGFloat(exp(delta))
                            canvasZoom = min(max(newZoom, 0.10), 4.0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    )
                    .overlay {
                        if let rect = marqueeRect {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.15))
                                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvasViewport"))
                            .onChanged { value in
                                handleMarqueeDrag(value: value)
                            }
                            .onEnded { value in
                                handleMarqueeEnd(value: value)
                            }
                    )
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                promptIsFocused = false
                            }
                    )
                    .onPreferenceChange(CardFramePreferenceKey.self) { frames in
                        cardFrames = frames
                    }
                    .onChange(of: cardFrames) { _, newFrames in
                        guard isDraggingMarquee, let rect = marqueeRect else { return }
                        let hits = Set(newFrames.compactMap { id, frame in
                            frame.intersects(rect) ? id : nil
                        })
                        let next = dragSelectedIDs.union(hits)
                        if next != dragSelectedIDs { dragSelectedIDs = next }
                        if next != viewModel.selectedItemIDs { viewModel.selectedItemIDs = next }
                    }
                    .onChange(of: canvasZoom) { _, _ in
                        if let id = viewModel.selectedItemID {
                            DispatchQueue.main.async {
                                withAnimation(.none) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                if let progress = viewModel.importProgress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text("\(progress.done)/\(progress.total)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                if viewModel.projects.isEmpty == false && viewModel.selectedFilteringProjectID == nil && !viewModel.isSearchActive {
                    Button {
                        viewModel.importImageToCanvas()
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18, height: 18)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .help("画像をインポート")
                }
                if !viewModel.projects.isEmpty && !canvasEntries.isEmpty {
                    Button {
                        viewModel.canvasSortOrder = viewModel.canvasSortOrder == .createdAtAscending ? .createdAtDescending : .createdAtAscending
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 13, weight: .medium))
                            Text(viewModel.canvasSortOrder == .createdAtDescending ? "Newest First" : "Oldest First")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)

                    Button {
                        viewModel.toggleSelectionMode()
                    } label: {
                        Image(systemName: viewModel.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18, height: 18)
                            .foregroundStyle(viewModel.isSelectionMode ? Color.accentColor : Color.primary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(viewModel.isSelectionMode ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .help(viewModel.isSelectionMode ? LocalizedStringKey("選択モード終了") : LocalizedStringKey("選択モード"))

                    let total = viewModel.displayedItemsSnapshot.count
                    let selected = viewModel.selectedItemIDs.count
                    Text(viewModel.isSelectionMode ? "\(selected)/\(total)" : "\(total)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(viewModel.isSelectionMode ? Color.accentColor : Color.secondary)
                        .frame(height: 34)
                        .padding(.horizontal, 8)

                    if viewModel.isSelectionMode {
                        Button {
                            guard EntitlementGate.shared.requireUnlocked() else { return }
                            viewModel.exportSelectedBatch()
                        } label: {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 18, height: 18)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                        .disabled(viewModel.selectedItemIDs.isEmpty)
                        .help("選択画像を一括エクスポート")

                        Button {
                            isConfirmingBatchDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Color.red)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                        .disabled(viewModel.selectedItemIDs.isEmpty)
                        .help("選択画像を一括削除")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.importProgress != nil)
            .padding(.top, 16)
            .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
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

    var canvasEntries: [CanvasEntry] {
        let persistedItems = viewModel.displayedItemsSnapshot.map { CanvasEntry.item($0) }
        let showJobs = viewModel.isGeneratingForSelected && viewModel.selectedFilteringProjectID == nil && !viewModel.isSearchActive
        let inProgressJobs = showJobs ? viewModel.currentJobs.map { CanvasEntry.job($0) } : []
        switch viewModel.canvasSortOrder {
        case .createdAtAscending: return persistedItems + inProgressJobs
        case .createdAtDescending: return inProgressJobs + persistedItems
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
                       let sourceItem = viewModel.items.first(where: { $0.id == sourceID }) {
                        let thumbSize = 36 * max(0.7, min(canvasZoom, 1.6))
                        ItemThumbnailView(
                            thumbnailStore: viewModel.thumbnailStore,
                            item: sourceItem,
                            originalURL: viewModel.fileURL(for: sourceItem),
                            contentMode: .fill
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
                    ZStack {
                        checkerboard
                        previewForItem(item)
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
                        }
                    }
                }
            }
        .onTapGesture(count: 2) {
            expandedItem = item
        }
        .onTapGesture(count: 1) {
            if viewModel.isSelectionMode {
                viewModel.toggleMultiSelection(item)
            } else {
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
                    contentMode: .fit
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
            enableOriginalUpgrade: true
        )
    }

    @ViewBuilder
    func preview(for job: GenerationJob) -> some View {
        JobPreviewView(job: job, onStop: viewModel.stopServer)
    }

    var checkerboard: some View {
        CheckerboardView(isDark: colorScheme == .dark)
    }

    @ViewBuilder
    var canvasActionPanel: some View {
        if let item = viewModel.items.first(where: { $0.id == viewModel.selectedItemID }),
           !viewModel.isSelectionMode {
            VStack(spacing: 6) {
                CircularPromptActionButton(
                    systemImage: "wand.and.stars",
                    tooltip: "再編集",
                    costLevel: viewModel.selectedModelCostLevel
                ) {
                    viewModel.edit(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "paintbrush.pointed",
                    tooltip: "マスク編集",
                    costLevel: viewModel.itemActionCostLevel
                ) {
                    guard EntitlementGate.shared.requireUnlocked() else { return }
                    viewModel.openMaskEditor(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "scissors",
                    tooltip: "背景を除去",
                    isDisabled: item.isBackgroundRemoved
                ) {
                    viewModel.startBackgroundRemoval(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "pointer.arrow.and.square.on.square.dashed",
                    tooltip: "素材として分離"
                ) {
                    viewModel.startMaterialExtraction(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "arrow.down.left.and.arrow.up.right.rectangle",
                    tooltip: "高解像度化",
                    costLevel: viewModel.itemActionCostLevel,
                    isDisabled: viewModel.upscalingItemIDs.contains(item.id)
                ) {
                    guard EntitlementGate.shared.requireUnlocked() else { return }
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
                    systemImage: "doc.on.doc",
                    tooltip: "複製"
                ) {
                    viewModel.duplicateItem(item)
                }
                CircularPromptActionButton(
                    systemImage: "square.and.arrow.up",
                    tooltip: "エクスポート"
                ) {
                    guard EntitlementGate.shared.requireUnlocked() else { return }
                    viewModel.exportItem(item)
                }
                CircularPromptActionButton(
                    systemImage: "folder",
                    tooltip: "Finderで表示"
                ) {
                    viewModel.reveal(item: item)
                }
                CircularPromptActionButton(
                    systemImage: "trash",
                    tooltip: "削除"
                ) {
                    confirmingDeleteItemID = item.id
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 2, y: 4)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }
}

struct ItemThumbnailView: View {
    @ObservedObject var thumbnailStore: CanvasThumbnailStore
    let item: ProjectItem
    let originalURL: URL
    let contentMode: ContentMode
    var cardSize: CGSize = .zero
    var originalStore: CanvasOriginalImageStore? = nil
    var enableOriginalUpgrade: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var originalImage: NSImage?
    @State private var loadTask: Task<Void, Never>?

    private var needsOriginal: Bool {
        guard enableOriginalUpgrade, originalStore != nil else { return false }
        return CanvasResolutionPolicy.requiresOriginal(cardSize: cardSize, screenScale: displayScale)
    }

    var body: some View {
        ZStack {
            if let nsImage = thumbnailStore.thumbnail(for: item, originalURL: originalURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.secondary.opacity(0.08)
                    .overlay(ProgressView().controlSize(.small))
            }
            if let original = originalImage {
                Image(nsImage: original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: originalImage != nil)
        .onAppear {
            if needsOriginal { applyNeedsOriginal(true) }
        }
        .onChange(of: needsOriginal) { _, newValue in
            applyNeedsOriginal(newValue)
        }
        .onDisappear {
            loadTask?.cancel()
            originalImage = nil
        }
    }

    private func applyNeedsOriginal(_ needs: Bool) {
        loadTask?.cancel()
        guard needs else {
            originalImage = nil
            return
        }
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let store = originalStore else { return }
            if let cached = store.cached(for: originalURL) {
                withAnimation { originalImage = cached }
                return
            }
            if let img = await store.loadIfNeeded(url: originalURL) {
                withAnimation { originalImage = img }
            }
        }
    }
}

struct JobPreviewView: View {
    let job: GenerationJob
    let onStop: () -> Void
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else if job.status == .failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(job.errorMessage ?? L("生成に失敗しました"))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            } else {
                GenerationProgressView(onStop: onStop)
            }
        }
        .task(id: job.imageData) {
            guard let data = job.imageData else { nsImage = nil; return }
            nsImage = await Task.detached(priority: .utility) { NSImage(data: data) }.value
        }
    }
}

struct MultiDragPreview: View {
    let items: [ProjectItem]
    let total: Int
    @ObservedObject var viewModel: DraftCanvasViewModel

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated().reversed()), id: \.element.id) { idx, item in
                ItemThumbnailView(
                    thumbnailStore: viewModel.thumbnailStore,
                    item: item,
                    originalURL: viewModel.fileURL(for: item),
                    contentMode: .fill
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                .rotationEffect(.degrees(Double(idx) * -4 + 4))
                .offset(x: CGFloat(idx) * 4, y: CGFloat(idx) * 4)
            }
        }
        .frame(width: 96, height: 96)
        .overlay(alignment: .topTrailing) {
            Text("\(total)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor))
                .overlay(Capsule().stroke(.white, lineWidth: 1))
                .padding(4)
        }
    }
}

private struct CheckerboardView: View {
    let isDark: Bool

    private static var lightImage: NSImage?
    private static var darkImage: NSImage?

    var body: some View {
        Image(nsImage: checkerImage)
            .resizable(resizingMode: .tile)
    }

    private var checkerImage: NSImage {
        if isDark, let img = Self.darkImage { return img }
        if !isDark, let img = Self.lightImage { return img }
        let img = renderChecker(isDark: isDark)
        if isDark { Self.darkImage = img } else { Self.lightImage = img }
        return img
    }

    private func renderChecker(isDark: Bool) -> NSImage {
        let side: CGFloat = 18
        let size = NSSize(width: side * 2, height: side * 2)
        let img = NSImage(size: size)
        img.lockFocus()
        let light: NSColor = isDark ? .white.withAlphaComponent(0.18) : .white
        let dark: NSColor = isDark ? .white.withAlphaComponent(0.06) : .black.withAlphaComponent(0.045)
        let tiles: [(CGRect, NSColor)] = [
            (CGRect(x: 0, y: 0, width: side, height: side), light),
            (CGRect(x: side, y: 0, width: side, height: side), dark),
            (CGRect(x: 0, y: side, width: side, height: side), dark),
            (CGRect(x: side, y: side, width: side, height: side), light),
        ]
        for (rect, color) in tiles {
            color.setFill()
            NSBezierPath(rect: rect).fill()
        }
        img.unlockFocus()
        return img
    }
}

struct AutoScrollerAnchor: NSViewRepresentable {
    let scroller: CanvasAutoScroller

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        scroller.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scroller.hostView = nsView
    }
}

struct CardFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension ContentView {
    func handleMarqueeDrag(value: DragGesture.Value) {
        guard !viewModel.projects.isEmpty && !canvasEntries.isEmpty else { return }
        if !isDraggingMarquee {
            let isOnCard = cardFrames.values.contains { $0.contains(value.startLocation) }
            if isOnCard {
                isDragStartedOnCard = true
                return
            }
            isDragStartedOnCard = false
            isDraggingMarquee = true
            viewModel.isSelectionMode = true
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            marqueeAdditive = flags.contains(.shift) || flags.contains(.command)
            dragSelectedIDs = marqueeAdditive ? viewModel.selectedItemIDs : []
        }
        guard !isDragStartedOnCard else { return }
        let s = value.startLocation
        let c = value.location
        let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(s.x - c.x), height: abs(s.y - c.y))
        marqueeRect = rect
        let hits = Set(cardFrames.compactMap { id, frame in frame.intersects(rect) ? id : nil })
        dragSelectedIDs = dragSelectedIDs.union(hits)
        viewModel.selectedItemIDs = dragSelectedIDs
        canvasAutoScroller.updateVelocity(mouseY: c.y, viewHeight: canvasViewportHeight)
        if canvasAutoScroller.velocity != 0 { canvasAutoScroller.start() } else { canvasAutoScroller.stop() }
    }

    func handleMarqueeEnd(value: DragGesture.Value) {
        canvasAutoScroller.stop()
        marqueeRect = nil
        isDraggingMarquee = false
        isDragStartedOnCard = false
        dragSelectedIDs = []
    }
}
