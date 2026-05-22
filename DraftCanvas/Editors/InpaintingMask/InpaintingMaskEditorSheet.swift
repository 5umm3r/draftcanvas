import SwiftUI
import AppKit

// MARK: - Sheet

struct InpaintingMaskEditorSheet: View {
    let originalImage: NSImage
    @Binding var mode: InpaintMode
    let onComplete: ([MaskStroke]) -> Void
    let onCancel: () -> Void

    @State private var strokes: [MaskStroke]
    @State private var undoneStrokes: [MaskStroke] = []

    init(originalImage: NSImage, mode: Binding<InpaintMode>, initialStrokes: [MaskStroke] = [],
         onComplete: @escaping ([MaskStroke]) -> Void, onCancel: @escaping () -> Void) {
        self.originalImage = originalImage
        self._mode = mode
        self._strokes = State(initialValue: initialStrokes)
        self.onComplete = onComplete
        self.onCancel = onCancel
    }
    @State private var brushRadius: CGFloat = 20
    @State private var isEraser: Bool = false
    @State private var isConfirmingClear: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            MaskCanvasView(
                originalImage: originalImage,
                strokes: $strokes,
                brushRadius: brushRadius,
                isEraser: isEraser,
                onStrokeCommit: { undoneStrokes = [] }
            )
        }
        .frame(minWidth: 800, minHeight: 620)
        .confirmationDialog("マスクをすべて消去しますか？", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("消去", role: .destructive) {
                strokes = []
                undoneStrokes = []
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onKeyPress(.init("[")) { brushRadius = max(5, brushRadius - 5); return .handled }
        .onKeyPress(.init("]")) { brushRadius = min(80, brushRadius + 5); return .handled }
        .onKeyPress(.init("e")) { isEraser.toggle(); return .handled }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $brushRadius, in: 5 ... 80, step: 1)
                .frame(width: 120)
            Text("\(Int(brushRadius))px")
                .font(.caption.monospacedDigit())
                .frame(width: 36)

            Toggle(isOn: $isEraser) {
                Image(systemName: "eraser")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)

            Divider().frame(height: 20)

            HStack(spacing: 4) {
                Button {
                    guard let last = strokes.last else { return }
                    undoneStrokes.append(last)
                    strokes.removeLast()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    guard let last = undoneStrokes.last else { return }
                    strokes.append(last)
                    undoneStrokes.removeLast()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(undoneStrokes.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Button {
                isConfirmingClear = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(strokes.isEmpty)

            Spacer()

            Picker("", selection: $mode) {
                Text("編集").tag(InpaintMode.edit)
                Text("除去").tag(InpaintMode.remove)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            Divider().frame(height: 20)

            Button("キャンセル", role: .cancel) { onCancel() }
                .fixedSize()
                .keyboardShortcut(.escape, modifiers: [])

            Button(mode == .remove ? LocalizedStringKey("除去") : LocalizedStringKey("完了")) { onComplete(strokes) }
                .buttonStyle(.borderedProminent)
                .disabled(strokes.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
