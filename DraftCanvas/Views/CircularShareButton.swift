import SwiftUI

struct CircularShareButton: View {
    let urls: [URL]
    @State private var isHovered = false

    var body: some View {
        ShareLink(items: urls) {
            Image(systemName: "paperplane")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(isHovered ? 0.12 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(urls.isEmpty)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .overlay(alignment: .center) {
            if isHovered {
                Text("共有")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .fixedSize()
                    .offset(x: 60)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .zIndex(isHovered ? 100 : 0)
    }
}
