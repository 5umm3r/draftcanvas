import SwiftUI
import AppKit

// MARK: - Sheet

struct CropEditorSheet: View {
    let sourceImage: NSImage
    let initialParams: CropParameters?
    let onComplete: (CGRect, AspectTemplate) -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect
    @State private var selectedTemplate: AspectTemplate
    @State private var displaySize: CGSize

    init(sourceImage: NSImage,
         initialParams: CropParameters? = nil,
         onComplete: @escaping (CGRect, AspectTemplate) -> Void,
         onCancel: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self.initialParams = initialParams
        self.onComplete = onComplete
        self.onCancel = onCancel

        let pixSize = Self.pixelSize(of: sourceImage)
        let fullRect = CGRect(origin: .zero, size: pixSize)
        if let p = initialParams {
            self._cropRect = State(initialValue: p.rect)
            self._selectedTemplate = State(initialValue: p.template)
            self._displaySize = State(initialValue: p.rect.size)
        } else {
            self._cropRect = State(initialValue: fullRect)
            self._selectedTemplate = State(initialValue: .freeform)
            self._displaySize = State(initialValue: fullRect.size)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            CropCanvasView(
                image: sourceImage,
                cropRect: $cropRect,
                template: selectedTemplate,
                onSizeChange: { size in
                    displaySize = size
                }
            )
        }
        .frame(minWidth: 800, minHeight: 620)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $selectedTemplate) {
                ForEach(AspectTemplate.allCases, id: \.self) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()

            Text("\(Int(displaySize.width.rounded())) × \(Int(displaySize.height.rounded())) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                resetToFullImage()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("画像全体にリセット")

            Spacer()

            Button("キャンセル", role: .cancel) { onCancel() }
                .fixedSize()
                .keyboardShortcut(.escape, modifiers: [])

            Button("完了") { onComplete(cropRect, selectedTemplate) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func resetToFullImage() {
        let pixSize = Self.pixelSize(of: sourceImage)
        let full = CGRect(origin: .zero, size: pixSize)
        if let ratio = selectedTemplate.ratio {
            cropRect = Self.largestInscribed(ratio: ratio, in: full)
        } else {
            cropRect = full
        }
        displaySize = cropRect.size
    }

    static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let ph = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            if pw > 0, ph > 0 { return CGSize(width: pw, height: ph) }
        }
        return image.size
    }

    static func largestInscribed(ratio: CGFloat, in rect: CGRect) -> CGRect {
        let candidateW = rect.width
        let candidateH = candidateW / ratio
        if candidateH <= rect.height {
            return CGRect(
                x: rect.midX - candidateW / 2,
                y: rect.midY - candidateH / 2,
                width: candidateW,
                height: candidateH
            )
        } else {
            let h = rect.height
            let w = h * ratio
            return CGRect(
                x: rect.midX - w / 2,
                y: rect.midY - h / 2,
                width: w,
                height: h
            )
        }
    }
}
