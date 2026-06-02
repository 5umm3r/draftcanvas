import SwiftUI
import os.signpost

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
            let actionPanelVisible: Bool =
                !viewModel.isSelectionMode
                && viewModel.selectedItemID != nil
                && viewModel.items.contains(where: { $0.id == viewModel.selectedItemID })
            let actionPanelReservation: CGFloat = 96
            let promptStandardPad: CGFloat = 24
            let needShift = actionPanelVisible && geometry.size.width < (actionPanelReservation + 780 + promptStandardPad)
            let promptLeading: CGFloat = needShift ? actionPanelReservation : promptStandardPad

            ZStack(alignment: .bottom) {
                canvas

                VStack(spacing: 8) {
                    if viewModel.isGeneratingForSelected {
                        HStack {
                            Spacer()
                            Button {
                                if let pid = viewModel.effectiveProjectID ?? viewModel.selectedProjectID {
                                    viewModel.cancelProjectRuns(projectID: pid)
                                }
                            } label: {
                                Label(String(localized: "停止"), systemImage: "stop.fill")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        }
                        .frame(maxWidth: 780)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        HStack {
                            Spacer()
                            retryFailedJobsButton
                            Spacer()
                        }
                        .frame(maxWidth: 780)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if viewModel.isTemplatePopoverPresented {
                        PromptTemplatePanel(viewModel: viewModel)
                            .frame(maxWidth: 780)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if viewModel.isHistoryPopoverPresented {
                        PromptHistoryPanel(viewModel: viewModel)
                            .frame(maxWidth: 780)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    promptPanel(maxPromptHeight: geometry.size.height / 2)
                }
                .padding(.leading, promptLeading)
                .padding(.trailing, promptStandardPad)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isGeneratingForSelected)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isTemplatePopoverPresented)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isHistoryPopoverPresented)

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
                            Text(String(localized: "\(progress.done) / \(progress.total) 枚処理中…"))
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
            .sheet(item: $viewModel.cropTarget) { item in
                cropEditorSheet(for: item)
                    .environment(\.locale, l10n.locale)
            }
            .sheet(item: $viewModel.sketchEditorTarget) { target in
                sketchEditorSheet(for: target)
                    .environment(\.locale, l10n.locale)
            }
            .sheet(item: $viewModel.outpaintTarget) { target in
                outpaintEditorSheet(for: target)
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

    @ViewBuilder
    func outpaintEditorSheet(for target: OutpaintTarget) -> some View {
        let item = target.item
        if let nsImage = viewModel.cachedImage(for: item) {
            OutpaintEditorSheet(
                sourceImage: nsImage,
                initialInsets: target.initialInsets,
                onComplete: { completion in
                    switch completion {
                    case .generate(let insets):
                        viewModel.applyOutpaint(item: item, insets: insets)
                    case .prompt(let insets):
                        viewModel.prepareOutpaint(item: item, insets: insets)
                    }
                },
                onCancel: {
                    viewModel.outpaintTarget = nil
                }
            )
        } else {
            Text("画像を読み込めませんでした")
                .padding(40)
        }
    }

    @ViewBuilder
    func cropEditorSheet(for item: ProjectItem) -> some View {
        // isCropped アイテムの再編集は元画像を表示する
        let sourceItem: ProjectItem = item.isCropped
            ? (viewModel.items.first(where: { $0.id == item.editedFromItemID }) ?? item)
            : item
        if let nsImage = viewModel.cachedImage(for: sourceItem) {
            CropEditorSheet(
                sourceImage: nsImage,
                initialParams: item.isCropped ? viewModel.projectStore.readCropParameters(id: item.id) : nil,
                onComplete: { rect, template in
                    viewModel.commitCrop(item: item, rect: rect, template: template)
                },
                onCancel: {
                    viewModel.cropTarget = nil
                }
            )
        } else {
            Text("画像を読み込めませんでした")
                .padding(40)
        }
    }

    @ViewBuilder
    func sketchEditorSheet(for target: SketchEditorTarget) -> some View {
        let initialStrokes = target.existingAttachment.map { viewModel.loadSketchStrokes(for: $0) } ?? []
        SketchEditorSheet(
            canvasPixelSize: target.canvasPixelSize,
            initialStrokes: initialStrokes,
            onComplete: { strokes in
                viewModel.applySketch(
                    strokes: strokes,
                    canvasPixelSize: target.canvasPixelSize,
                    existingID: target.existingAttachment?.id
                )
                viewModel.sketchEditorTarget = nil
            },
            onCancel: {
                viewModel.sketchEditorTarget = nil
            }
        )
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
                    .focusable(true)
                    .focusEffectDisabled()
                    .focused($canvasIsFocused)
                    .onKeyPress(.leftArrow)  { handleArrow(.left) }
                    .onKeyPress(.rightArrow) { handleArrow(.right) }
                    .onKeyPress(.upArrow)    { handleArrow(.up) }
                    .onKeyPress(.downArrow)  { handleArrow(.down) }
                    .onKeyPress(.space)      { handleSpace() }
                    .onTapGesture {
                        viewModel.selectedItemID = nil
                        viewModel.selectedJobID = nil
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    canvasViewportHeight = geo.size.height
                                    canvasViewportWidth = geo.size.width
                                }
                                .onChange(of: geo.size) { _, s in
                                    canvasViewportHeight = s.height
                                    canvasViewportWidth = s.width
                                }
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
                                canvasIsFocused = true
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.isTemplatePopoverPresented = false
                                    viewModel.isHistoryPopoverPresented = false
                                }
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
                    .onChange(of: viewModel.selectedItemID) { _, newID in
                        guard let id = newID else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: .center)
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

                        let shareURLs = viewModel.displayedItemsSnapshot
                            .filter { viewModel.selectedItemIDs.contains($0.id) }
                            .map { viewModel.projectStore.resolvedFileURL(for: $0) }
                        ShareLink(items: shareURLs) {
                            Image(systemName: "paperplane")
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
                        .help("選択画像を一括共有")

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

    var canvasGridColumns: Int {
        let minSide = CanvasCardLayout.baseSquareSide * canvasZoom
        let spacing = CanvasCardLayout.spacing(zoom: canvasZoom)
        let usable = max(0, canvasViewportWidth - 84 - 24)
        return max(1, Int((usable + spacing) / (minSide + spacing)))
    }

    private func handleArrow(_ dir: CanvasMoveDirection) -> KeyPress.Result {
        guard expandedItem == nil else { return .ignored }
        viewModel.moveCanvasSelection(direction: dir, columns: canvasGridColumns)
        return .handled
    }

    private func handleSpace() -> KeyPress.Result {
        guard expandedItem == nil, let target = viewModel.canvasPreviewTarget else {
            return .ignored
        }
        expandedItem = target
        return .handled
    }
}
