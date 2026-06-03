import SwiftUI

struct GenerationProgressView: View {
    let prompt: String
    let seed: Int
    @AppStorage("placeholderAnimationStyle") private var animationStyleRaw: String = PlaceholderAnimationStyle.aurora.rawValue
    @State private var isHovering = false
    @State private var showPromptOverlay = false
    @State private var promptDelayTask: Task<Void, Never>?

    private var animationStyle: PlaceholderAnimationStyle {
        PlaceholderAnimationStyle(rawValue: animationStyleRaw) ?? .aurora
    }

    var body: some View {
        PlaceholderAnimationView(style: animationStyle, seed: seed)
        .overlay(alignment: .bottom) {
            if showPromptOverlay && !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 6,
                            bottomTrailingRadius: 6,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showPromptOverlay)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                promptDelayTask?.cancel()
                promptDelayTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled {
                        showPromptOverlay = true
                    }
                }
            } else {
                promptDelayTask?.cancel()
                showPromptOverlay = false
            }
        }
    }
}
