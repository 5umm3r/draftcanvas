import SwiftUI

enum OutpaintCompletion {
    case generate(OutpaintInsets)
    case prompt(OutpaintInsets)
}

struct OutpaintEditorSheet: View {
    let sourceImage: NSImage
    let initialInsets: OutpaintInsets
    let onComplete: (OutpaintCompletion) -> Void
    let onCancel: () -> Void

    @State private var insets: OutpaintInsets
    @State private var expandedSize: CGSize = .zero
    @State private var selectedRatio: GenerationAspectRatio = .auto

    init(sourceImage: NSImage,
         initialInsets: OutpaintInsets = .zero,
         onComplete: @escaping (OutpaintCompletion) -> Void,
         onCancel: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self.initialInsets = initialInsets
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._insets = State(initialValue: initialInsets)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            OutpaintCanvasView(
                image: sourceImage,
                insets: $insets
            )
            .onChange(of: insets) { newInsets in
                let pixSize = Self.pixelSize(of: sourceImage)
                expandedSize = newInsets.expandedSize(from: pixSize)
            }
        }
        .frame(minWidth: 800, minHeight: 620)
        .onAppear {
            expandedSize = Self.pixelSize(of: sourceImage)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                insets = .zero
                selectedRatio = .auto
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("拡張をリセット")
            .disabled(insets.isEmpty)

            ratioMenu

            Spacer()

            HStack(spacing: 8) {
                insetsLabel("arrow.up", insets.top)
                insetsLabel("arrow.down", insets.bottom)
                insetsLabel("arrow.left", insets.left)
                insetsLabel("arrow.right", insets.right)
            }

            Text("\(Int(expandedSize.width.rounded())) × \(Int(expandedSize.height.rounded())) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button("キャンセル", role: .cancel) { onCancel() }
                .fixedSize()
                .keyboardShortcut(.escape, modifiers: [])

            Button("プロンプト入力して拡張") { onComplete(.prompt(insets)) }
                .disabled(insets.isEmpty)

            Button("拡張して生成") { onComplete(.generate(insets)) }
                .buttonStyle(.borderedProminent)
                .disabled(insets.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var ratioMenu: some View {
        Menu {
            ForEach(GenerationAspectRatio.allCases) { ratio in
                Button {
                    applyRatioPreset(ratio)
                } label: {
                    HStack {
                        Text(ratio.displayLabel)
                        if selectedRatio == ratio {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "aspectratio")
                Text(selectedRatio.displayLabel)
                    .font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func applyRatioPreset(_ ratio: GenerationAspectRatio) {
        selectedRatio = ratio
        guard ratio != .auto else { return }

        let pixSize = Self.pixelSize(of: sourceImage)
        guard pixSize.width > 0, pixSize.height > 0 else { return }

        let targetRatio = ratio.widthOverHeight
        let currentRatio = pixSize.width / pixSize.height

        var newInsets = OutpaintInsets.zero
        if targetRatio > currentRatio {
            let newW = pixSize.height * targetRatio
            let addW = newW - pixSize.width
            newInsets.left = round(addW / 2)
            newInsets.right = round(addW / 2)
        } else if targetRatio < currentRatio {
            let newH = pixSize.width / targetRatio
            let addH = newH - pixSize.height
            newInsets.top = round(addH / 2)
            newInsets.bottom = round(addH / 2)
        }

        insets = newInsets
        expandedSize = newInsets.expandedSize(from: pixSize)
    }

    @ViewBuilder
    private func insetsLabel(_ systemImage: String, _ value: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(value > 0 ? .primary : .secondary)
        }
    }

    static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let ph = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            if pw > 0, ph > 0 { return CGSize(width: pw, height: ph) }
        }
        return image.size
    }
}
