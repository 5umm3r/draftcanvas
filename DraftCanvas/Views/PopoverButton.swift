import SwiftUI

struct PopoverButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var disabledReason: String? = nil
    var showCostBadge: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showCostBadge {
                    CodexCostBadge()
                }
            }
        }
        .disabled(isDisabled)
        .help(disabledReason ?? "")
    }
}
