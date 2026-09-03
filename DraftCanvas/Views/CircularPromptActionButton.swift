import SwiftUI

extension Color {
    /// ブックマーク表示に使う青系の共通色。白いバッジでは画像上で目立たないため専用色を持つ。
    static let bookmarkTint = Color(nsColor: .systemBlue)
}

struct CircularPromptActionButton: View {
    let systemImage: String
    let tooltip: LocalizedStringKey
    var showCostBadge: Bool = false
    var isDisabled: Bool = false
    var isAccent: Bool = false
    var isDestructive: Bool = false
    /// 塗りつぶしに使う色。nil の場合は accentColor を使う。
    var accentTint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isAccent ? Color.white : (isDestructive ? Color.red : Color.primary))
                    .frame(width: 36, height: 36)
                    .background(
                        isAccent
                            ? AnyShapeStyle((accentTint ?? Color.accentColor).opacity(isHovered ? 0.85 : 1.0))
                            : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.12 : 0.06)),
                        in: Circle()
                    )
                if showCostBadge {
                    CodexCostBadge()
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
