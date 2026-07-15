import SwiftUI
import AppKit

private enum UpscalePreviewZoomMode: String, CaseIterable, Identifiable {
    case fit
    case actual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "フィット"
        case .actual: return "100%"
        }
    }
}

struct UpscalePreviewSheet: View {
    let payload: UpscalePreviewPayload
    @ObservedObject var viewModel: DraftCanvasViewModel
    let onApply: (UpscaleApplyMode) -> Void

    @State private var dividerPosition: CGFloat = 0.5
    @State private var isDragging = false
    // ドラッグ中は dividerPosition の変化で body が毎フレーム再評価されるため、
    // 大判画像のデコードは一度だけ行い @State に保持する
    @State private var beforeImage: NSImage?
    @State private var afterImage: NSImage?
    @State private var zoomMode: UpscalePreviewZoomMode = .fit

    // モデル切替時は payload ごと差し替わるため id は payload.id で追跡する
    var body: some View {
        VStack(spacing: 0) {
            comparisonArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            controlBar
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 1100, idealWidth: 1400, minHeight: 750, idealHeight: 900)
        .task(id: payload.id) {
            let upscaledData = payload.upscaledImageData
            let originalData = payload.originalImageData
            async let after = Task.detached(priority: .userInitiated) { NSImage(data: upscaledData) }.value
            async let before = Task.detached(priority: .userInitiated) { NSImage(data: originalData) }.value
            afterImage = await after
            beforeImage = await before
        }
    }

    // MARK: - Comparison

    @ViewBuilder
    private var comparisonArea: some View {
        switch zoomMode {
        case .fit:
            fitComparison
        case .actual:
            actualComparison
        }
    }

    private var fitComparison: some View {
        GeometryReader { geo in
            comparisonZStack(canvasSize: geo.size, useFitLayout: true)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { rerunOverlay }
    }

    private var actualComparison: some View {
        let pixelSize = actualPixelSize()
        return ScrollView([.horizontal, .vertical]) {
            comparisonZStack(canvasSize: pixelSize, useFitLayout: false)
                .frame(width: pixelSize.width, height: pixelSize.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { rerunOverlay }
    }

    private func actualPixelSize() -> CGSize {
        if let after = afterImage, let size = pixelSize(of: after) {
            return size
        }
        if let after = afterImage {
            return after.size
        }
        return CGSize(width: 1024, height: 1024)
    }

    private func pixelSize(of image: NSImage) -> CGSize? {
        guard let rep = image.representations.first else { return nil }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    private func comparisonZStack(canvasSize: CGSize, useFitLayout: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if let after = afterImage {
                imageView(after, useFitLayout: useFitLayout, size: canvasSize)
            }

            if let before = beforeImage {
                imageView(before, useFitLayout: useFitLayout, size: canvasSize)
                    .clipShape(
                        Rectangle().path(in: CGRect(
                            x: 0, y: 0,
                            width: canvasSize.width * dividerPosition,
                            height: canvasSize.height
                        ))
                    )
            }

            // Divider line
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: canvasSize.height)
                .offset(x: canvasSize.width * dividerPosition - 1)
                .shadow(radius: 2)

            // Drag handle
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(radius: 3)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                )
                .position(
                    x: canvasSize.width * dividerPosition,
                    y: canvasSize.height / 2
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let x = value.location.x
                            dividerPosition = min(1, max(0, x / canvasSize.width))
                        }
                )

            // Labels
            HStack {
                Text("元画像")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                Spacer()
            }
            .frame(width: canvasSize.width)

            HStack {
                Spacer()
                Text("高解像度化")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(width: canvasSize.width)
        }
        .clipped()
    }

    @ViewBuilder
    private func imageView(_ image: NSImage, useFitLayout: Bool, size: CGSize) -> some View {
        if useFitLayout {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var rerunOverlay: some View {
        if viewModel.upscaleRerunning {
            ZStack {
                Color.black.opacity(0.35)
                ProgressView("再アップスケール中…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button("破棄") {
                onApply(.discard)
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Picker("表示", selection: $zoomMode) {
                ForEach(UpscalePreviewZoomMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .disabled(viewModel.upscaleRerunning)

            Picker("モデル", selection: modelSelection) {
                ForEach(UpscaleModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .disabled(viewModel.upscaleRerunning)

            Spacer()

            Button("新規アイテムとして追加") {
                onApply(.addAsNew)
            }
            .disabled(viewModel.upscaleRerunning)

            Button("上書き保存") {
                onApply(.overwrite)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(viewModel.upscaleRerunning)
        }
    }

    private var modelSelection: Binding<UpscaleModel> {
        Binding(
            get: { payload.model },
            set: { viewModel.rerunUpscale(payload: payload, model: $0) }
        )
    }
}
