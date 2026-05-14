import SwiftUI

struct PopoverButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var disabledReason: String? = nil
    var costLevel: Int? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let level = costLevel {
                    CodexCostBadge(level: level)
                }
            }
        }
        .disabled(isDisabled)
        .help(disabledReason ?? "")
    }
}
