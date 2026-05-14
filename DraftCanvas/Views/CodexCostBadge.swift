import SwiftUI

struct CodexCostBadge: View {
    let level: Int

    var body: some View {
        if level > 0 {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Codexコスト")
        }
    }
}
