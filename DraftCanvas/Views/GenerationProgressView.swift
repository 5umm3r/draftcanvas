import SwiftUI

struct GenerationProgressView: View {
    let onStop: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isHovering {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                AuroraPlaceholderView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
