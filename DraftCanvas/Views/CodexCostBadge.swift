import SwiftUI

struct CodexCostBadge: View {
    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Codexコスト")
    }
}
