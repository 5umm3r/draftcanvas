import SwiftUI

struct PromptHistoryPopover: View {
    let entries: [PromptHistoryEntry]
    let onSelect: (PromptHistoryEntry) -> Void
    let onDelete: (UUID) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Text("履歴")
                    .font(.headline)
                Spacer()
                if !entries.isEmpty {
                    Button("すべて削除") { onClear() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            if entries.isEmpty {
                Text("履歴がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            PromptHistoryRow(
                                entry: entry,
                                onSelect: { onSelect(entry) },
                                onDelete: { onDelete(entry.id) }
                            )
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 340)
    }
}

private struct PromptHistoryRow: View {
    let entry: PromptHistoryEntry
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Text(entry.prompt)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
    }
}
