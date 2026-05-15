import SwiftUI
import AppKit

struct UpscalePreviewSheet: View {
    let payload: UpscalePreviewPayload
    let onApply: (UpscaleApplyMode) -> Void

    @State private var dividerPosition: CGFloat = 0.5
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            comparisonArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            controlBar
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 700, minHeight: 520)
    }

    // MARK: - Comparison

    private var comparisonArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let after = NSImage(data: payload.upscaledImageData) {
                    Image(nsImage: after)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let before = NSImage(data: payload.originalImageData) {
                    Image(nsImage: before)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(
                            Rectangle().path(in: CGRect(
                                x: 0, y: 0,
                                width: geo.size.width * dividerPosition,
                                height: geo.size.height
                            ))
                        )
                }

                // Divider line
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: geo.size.width * dividerPosition - 1)
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
                        x: geo.size.width * dividerPosition,
                        y: geo.size.height / 2
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dividerPosition = min(1, max(0, value.location.x / geo.size.width))
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

                HStack {
                    Spacer()
                    Text("高解像度化")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button("破棄") {
                onApply(.discard)
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("新規アイテムとして追加") {
                onApply(.addAsNew)
            }

            Button("上書き保存") {
                onApply(.overwrite)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }
}
