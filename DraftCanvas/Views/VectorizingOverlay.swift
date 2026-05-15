import SwiftUI

struct VectorizingOverlay: View {
    var label: LocalizedStringKey = "ベクター化中"
    let onCancel: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(isHovering ? 0.55 : 0.35))

            if isHovering {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.large)
                        .colorScheme(.dark)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
