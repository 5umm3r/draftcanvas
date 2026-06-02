import SwiftUI

struct BackgroundRemovalPreview: Identifiable {
    let id = UUID()
    let item: ProjectItem
    let session: BackgroundRemover.MaskSession
    let initialData: Data
}

struct BackgroundRemovalPreviewSheet: View {
    let preview: BackgroundRemovalPreview
    @ObservedObject var viewModel: DraftCanvasViewModel

    @State private var edgeStrength: Double = 0.5
    @State private var mode: BackgroundRemover.Mode
    @State private var currentData: Data
    @State private var isProcessing = false
    @State private var updateTask: Task<Void, Never>?

    init(preview: BackgroundRemovalPreview, viewModel: DraftCanvasViewModel) {
        self.preview = preview
        self.viewModel = viewModel
        self._currentData = State(initialValue: preview.initialData)
        self._mode = State(initialValue: preview.session.initialMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            controlBar
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 640, minHeight: 540)
        .onChange(of: edgeStrength) { scheduleUpdate() }
        .onChange(of: mode) { scheduleUpdate() }
    }

    // MARK: - Subviews

    private var previewArea: some View {
        ZStack {
            // Checkerboard background to visualise transparency
            CheckerboardView()

            if let image = NSImage(data: currentData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            }

            if isProcessing {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .clipShape(Rectangle())
    }

    private var edgeLabel: String {
        let px = Int((abs(edgeStrength - 0.5) * 20.0).rounded())
        if edgeStrength < 0.49 { return "-\(px)px" }
        if edgeStrength > 0.51 { return "+\(px)px" }
        return "0px"
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            // モード切替
            Picker("", selection: $mode) {
                Text("ロゴ").tag(BackgroundRemover.Mode.logo)
                Text("写真").tag(BackgroundRemover.Mode.photo)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .help(modePickerHelp)

            // 境界調整スライダー
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("境界調整")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(edgeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("収縮").font(.caption2).foregroundStyle(.tertiary)
                    Slider(value: $edgeStrength, in: 0...1)
                    Text("拡張").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 240)

            Spacer()

            Button("キャンセル") {
                viewModel.cancelBackgroundRemoval()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button(isProcessing ? LocalizedStringKey("処理中...") : LocalizedStringKey("保存")) {
                viewModel.commitBackgroundRemoval(item: preview.item, data: currentData)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var modePickerHelp: String {
        let logoAvail = preview.session.logoMaskCI != nil
        let photoAvail = preview.session.photoMaskCI != nil
        if logoAvail && photoAvail { return String(localized: "ロゴ: 色差ベース / 写真: AI検出") }
        if logoAvail { return String(localized: "ロゴモードのみ利用可能") }
        return String(localized: "写真モードのみ利用可能")
    }

    // MARK: - Real-time update

    private func scheduleUpdate() {
        updateTask?.cancel()
        updateTask = Task {
            // 80ms debounce — avoids flooding while dragging slider
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await renderPreview()
        }
    }

    @MainActor
    private func renderPreview() async {
        isProcessing = true
        let strength = edgeStrength
        let currentMode = mode
        let session = preview.session
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try BackgroundRemover.apply(session: session, edgeStrength: strength, mode: currentMode)
            }.value
            currentData = data
        } catch {
            // Keep last valid preview on failure
        }
        isProcessing = false
    }
}

// MARK: - Checkerboard

private struct CheckerboardView: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 12
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let color: Color = (row + col).isMultiple(of: 2) ? .white : Color(white: 0.85)
                    ctx.fill(
                        Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
