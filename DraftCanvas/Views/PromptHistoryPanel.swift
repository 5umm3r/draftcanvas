import SwiftUI

struct PromptHistoryPanel: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var hoveredEntryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    private var header: some View {
        HStack {
            Text("生成履歴")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if !viewModel.promptHistory.isEmpty {
                Button(String(localized: "全削除")) {
                    viewModel.clearHistory()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isHistoryPopoverPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.promptHistory.isEmpty {
                    Text("まだ履歴がありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(viewModel.promptHistory) { entry in
                        historyRow(entry: entry)
                        if entry.id != viewModel.promptHistory.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(entry: PromptHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.promptText)
                    .font(.caption)
                    .lineLimit(2)
                Text("\(entry.useCount)回使用")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button(String(localized: "適用")) {
                    viewModel.applyHistory(entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    viewModel.deleteHistoryEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hoveredEntryID == entry.id ? 1 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredEntryID = isHovering ? entry.id : nil
        }
    }
}
