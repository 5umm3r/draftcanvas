import SwiftUI
import AppKit

// MARK: - Sheet

struct SketchEditorSheet: View {
    let canvasPixelSize: CGSize
    let onComplete: ([SketchStroke]) -> Void
    let onCancel: () -> Void

    @State private var strokes: [SketchStroke]
    @State private var undoneStrokes: [SketchStroke] = []
    @State private var brushRadius: CGFloat = 20
    @State private var isEraser: Bool = false
    @State private var selectedColor: CodableColor = .black
    @State private var isConfirmingClear: Bool = false

    init(
        canvasPixelSize: CGSize,
        initialStrokes: [SketchStroke] = [],
        onComplete: @escaping ([SketchStroke]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.canvasPixelSize = canvasPixelSize
        self._strokes = State(initialValue: initialStrokes)
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            SketchCanvasView(
                canvasPixelSize: canvasPixelSize,
                strokes: $strokes,
                brushRadius: brushRadius,
                isEraser: isEraser,
                selectedColor: selectedColor,
                onStrokeCommit: { undoneStrokes = [] }
            )
        }
        .frame(minWidth: 800, minHeight: 620)
        .confirmationDialog("描画をすべて消去しますか？", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("消去", role: .destructive) {
                strokes = []
                undoneStrokes = []
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onKeyPress(.init("[")) { brushRadius = max(5, brushRadius - 5); return .handled }
        .onKeyPress(.init("]")) { brushRadius = min(80, brushRadius + 5); return .handled }
        .onKeyPress(.init("e")) { isEraser.toggle(); return .handled }
        .onKeyPress(.init("1")) { selectPreset(0); return .handled }
        .onKeyPress(.init("2")) { selectPreset(1); return .handled }
        .onKeyPress(.init("3")) { selectPreset(2); return .handled }
        .onKeyPress(.init("4")) { selectPreset(3); return .handled }
        .onKeyPress(.init("5")) { selectPreset(4); return .handled }
    }

    private func selectPreset(_ index: Int) {
        let presets = CodableColor.presets
        guard index < presets.count else { return }
        selectedColor = presets[index]
        isEraser = false
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // ブラシ径
            Image(systemName: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $brushRadius, in: 5 ... 80, step: 1)
                .frame(width: 100)
            Text("\(Int(brushRadius))px")
                .font(.caption.monospacedDigit())
                .frame(width: 36)

            Divider().frame(height: 20)

            // カラーパレット
            HStack(spacing: 4) {
                ForEach(0..<CodableColor.presets.count, id: \.self) { i in
                    let color = CodableColor.presets[i]
                    let isSelected = !isEraser && selectedColor == color
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                        )
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                        .onTapGesture {
                            selectedColor = color
                            isEraser = false
                        }
                }
            }

            Divider().frame(height: 20)

            // 消しゴム
            Toggle(isOn: $isEraser) {
                Image(systemName: "eraser")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)

            Divider().frame(height: 20)

            // Undo / Redo
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

            // Clear
            Button {
                isConfirmingClear = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(strokes.isEmpty)

            Spacer()

            Button("キャンセル", role: .cancel) { onCancel() }
                .fixedSize()
                .keyboardShortcut(.escape, modifiers: [])

            Button("完了") { onComplete(strokes) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
