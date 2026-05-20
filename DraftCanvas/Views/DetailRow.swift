import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String
    var trailing: AnyView? = nil
    var lineLimit: Int? = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
        }
    }
}
