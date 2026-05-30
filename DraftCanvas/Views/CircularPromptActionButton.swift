import SwiftUI

struct CircularPromptActionButton: View {
    let systemImage: String
    let tooltip: LocalizedStringKey
    var costLevel: Int? = nil
    var isDisabled: Bool = false
    var isAccent: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isAccent ? Color.white : Color.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        isAccent
                            ? AnyShapeStyle(Color.accentColor.opacity(isHovered ? 0.85 : 1.0))
                            : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.12 : 0.06)),
                        in: Circle()
                    )
                if let level = costLevel, level > 0 {
                    CodexCostBadge(level: level)
                        .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .overlay(alignment: .leading) {
            if isHovered {
                Text(tooltip)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .fixedSize()
                    .offset(x: 44)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .zIndex(isHovered ? 100 : 0)
    }
}
