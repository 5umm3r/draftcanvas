import SwiftUI
import AppKit

struct ExpandedImageSheet: View {
    let items: [ProjectItem]
    @ObservedObject var viewModel: DraftCanvasViewModel
    let onDismiss: () -> Void
    let onRequestDelete: (ProjectItem) -> Void

    @State private var currentItemID: ProjectItem.ID
    @State private var keyMonitor: Any?
    // cachedImage はメモリキャッシュ専用のため、ミス時は非同期で原本をロードする。
    // ロード完了までは ItemThumbnailView をプレースホルダとして表示する。
    @State private var fullImage: NSImage?
    @State private var magnification: CGFloat = 1.0
    @State private var fitMagnification: CGFloat = 1.0
    @State private var usesPixelInterpolation = false
    @State private var didCopy = false

    private let zoomStep: CGFloat = 1.5

    init(
        item: ProjectItem,
        items: [ProjectItem],
        viewModel: DraftCanvasViewModel,
        onDismiss: @escaping () -> Void,
        onRequestDelete: @escaping (ProjectItem) -> Void
    ) {
        self.items = items
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onRequestDelete = onRequestDelete
        self._currentItemID = State(initialValue: item.id)
    }

    private var currentItem: ProjectItem? { items.first(where: { $0.id == currentItemID }) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if let item = currentItem {
                imageContent(for: item)
                    .padding(.horizontal, 48)
                    .padding(.top, 72)
                    .padding(.bottom, items.count > 1 ? 72 : 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let item = currentItem {
                VStack {
                    HStack(spacing: 8) {
                        if fullImage != nil {
                            zoomControlBar
                        }
                        itemActionBar(for: item)
                    }
                    .padding(.top, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .keyboardShortcut(.escape, modifiers: [])

            if items.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: goPrevious) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        let displayIndex = items.firstIndex(where: { $0.id == currentItemID }).map { $0 + 1 } ?? 0
                        Text("\(displayIndex) / \(items.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())

                        Button(action: goNext) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: items) { oldItems, newItems in
            // 現在表示中の項目が新しい配列から消えた場合（削除、または「ブックマークのみ」
            // フィルタ中のブックマーク解除など）、旧配列でのインデックスを基準に近傍の項目へ
            // 移動する。配列が空になった場合のみプレビューを閉じる。
            guard !newItems.contains(where: { $0.id == currentItemID }) else { return }
            guard !newItems.isEmpty else {
                onDismiss()
                return
            }
            let oldIndex = oldItems.firstIndex(where: { $0.id == currentItemID }) ?? 0
            let newIndex = min(oldIndex, newItems.count - 1)
            currentItemID = newItems[newIndex].id
        }
        .task(id: currentItemID) {
            guard let item = currentItem else { return }
            fullImage = viewModel.cachedImage(for: item)
            if fullImage == nil {
                fullImage = await viewModel.loadImage(for: item)
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // ⌘ 単独修飾のときだけズーム操作に割り当てる（⌘W や ⌘⌥ 系は素通し）。
                // ⌘+ は shift を伴うため shift は判定から除外する。
                let flags = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting(.shift)
                if flags == .command {
                    switch event.charactersIgnoringModifiers {
                    case "+", "=":
                        guard fullImage != nil else { return event }
                        zoomIn(); return nil
                    case "-":
                        guard fullImage != nil else { return event }
                        zoomOut(); return nil
                    case "0":
                        guard fullImage != nil else { return event }
                        zoomToFit(); return nil
                    case "1":
                        guard fullImage != nil else { return event }
                        zoomToActualSize(); return nil
                    case "c":
                        guard fullImage != nil, let item = currentItem else { return event }
                        copyCurrentItem(item)
                        return nil
                    case "d":
                        guard let item = currentItem else { return event }
                        viewModel.duplicateItem(item)
                        return nil
                    case "b":
                        guard let item = currentItem else { return event }
                        viewModel.toggleBookmark(item)
                        return nil
                    case "e":
                        guard let item = currentItem else { return event }
                        exportCurrentItem(item)
                        return nil
                    default:
                        return event
                    }
                }

                switch event.keyCode {
                case 49:  onDismiss(); return nil    // Space
                case 123: goPrevious(); return nil  // ←
                case 124: goNext(); return nil       // →
                case 51, 117:                        // Delete / Forward Delete（修飾キーなしのみ）
                    let noModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                    guard noModifiers, let item = currentItem else { return event }
                    onRequestDelete(item)
                    return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private func imageContent(for item: ProjectItem) -> some View {
        if let nsImage = fullImage {
            // ズーム操作を受けるためヒットテストを有効にする。
            // 画像領域内のクリックでは閉じず、背景の余白・Esc・閉じるボタンで閉じる。
            ZoomableImageView(
                image: nsImage,
                magnification: $magnification,
                fitMagnification: $fitMagnification,
                usesPixelInterpolation: usesPixelInterpolation,
                onBackgroundClick: onDismiss
            )
        } else {
            ItemThumbnailView(
                thumbnailStore: viewModel.thumbnailStore,
                item: item,
                originalURL: viewModel.fileURL(for: item),
                contentMode: .fit,
                syncMonitor: viewModel.syncMonitor
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: - Zoom controls

    private var minMagnification: CGFloat {
        ZoomableImageView.minimumMagnification(forFit: fitMagnification)
    }

    private var isAtFit: Bool { abs(magnification - fitMagnification) < 0.005 }

    private var isAtActualSize: Bool { abs(magnification - 1.0) < 0.005 }

    private var zoomControlBar: some View {
        HStack(spacing: 6) {
            modeButton("フィット", isActive: isAtFit, action: zoomToFit)
            modeButton("100%", isActive: isAtActualSize, action: zoomToActualSize)

            controlSeparator

            iconButton("minus", help: "縮小", action: zoomOut)
                .disabled(magnification <= minMagnification + 0.0001)

            Text("\(Int((magnification * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 52)

            iconButton("plus", help: "拡大", action: zoomIn)
                .disabled(magnification >= ZoomableImageView.maxMagnification - 0.0001)

            controlSeparator

            iconButton(
                "square.grid.3x3",
                help: "ピクセル表示",
                isActive: usesPixelInterpolation
            ) {
                usesPixelInterpolation.toggle()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Item action bar

    private func itemActionBar(for item: ProjectItem) -> some View {
        HStack(spacing: 6) {
            iconButton(
                item.isBookmarked ? "bookmark.fill" : "bookmark",
                help: item.isBookmarked ? "ブックマークを解除" : "ブックマーク",
                isActive: item.isBookmarked,
                activeTint: .bookmarkTint
            ) {
                viewModel.toggleBookmark(item)
            }

            controlSeparator

            iconButton(
                didCopy ? "checkmark" : "doc.on.doc",
                help: didCopy ? "コピー完了" : "クリップボードにコピー"
            ) {
                copyCurrentItem(item)
            }
            .disabled(fullImage == nil)

            iconButton("plus.square.on.square", help: "複製") {
                viewModel.duplicateItem(item)
            }

            iconButton("trash", help: "削除") {
                onRequestDelete(item)
            }

            controlSeparator

            ShareLink(items: [viewModel.fileURL(for: item)]) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("共有")

            iconButton("square.and.arrow.down", help: "エクスポート") {
                exportCurrentItem(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func copyCurrentItem(_ item: ProjectItem) {
        Task {
            guard await viewModel.copyItemToClipboard(item) else { return }
            withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.2)) { didCopy = false }
            }
        }
    }

    private func exportCurrentItem(_ item: ProjectItem) {
        // エクスポートシートは ContentView 側で表示されるため、オーバーレイの下に
        // 隠れないよう先にプレビューを閉じてから次のランループでシートを要求する。
        onDismiss()
        DispatchQueue.main.async {
            viewModel.exportItem(item)
        }
    }

    private var controlSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 18)
    }

    private func modeButton(
        _ title: LocalizedStringKey,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.white.opacity(0.9) : Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        _ systemName: String,
        help: LocalizedStringKey,
        isActive: Bool = false,
        activeTint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? (activeTint == nil ? Color.black : Color.white) : Color.white)
                .frame(width: 24, height: 24)
                .background(isActive ? (activeTint ?? Color.white.opacity(0.9)) : Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func setMagnification(_ value: CGFloat) {
        magnification = min(max(value, minMagnification), ZoomableImageView.maxMagnification)
    }

    private func zoomIn() { setMagnification(magnification * zoomStep) }

    private func zoomOut() { setMagnification(magnification / zoomStep) }

    private func zoomToFit() { setMagnification(fitMagnification) }

    private func zoomToActualSize() { setMagnification(1.0) }

    private func goNext() {
        guard !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == currentItemID }) else { return }
        currentItemID = items[(idx + 1) % items.count].id
    }

    private func goPrevious() {
        guard !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == currentItemID }) else { return }
        currentItemID = items[(idx - 1 + items.count) % items.count].id
    }
}
