import SwiftUI

struct PromptHistoryPanel: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var hoveredEntryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            historyContent
            Divider()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    // MARK: - Content

    private var historyContent: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if viewModel.promptHistory.isEmpty {
                    Text("まだ履歴がありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(viewModel.promptHistory) { entry in
                        historyCard(entry: entry)
                    }
                    if viewModel.promptHistory.count > 1 {
                        Button(String(localized: "全削除")) {
                            viewModel.clearHistory()
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - History Card

    private func historyCard(entry: PromptHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.promptText)
                .font(.caption)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Text("\(entry.useCount)回使用")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        viewModel.deleteHistoryEntry(entry)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hoveredEntryID == entry.id ? 1 : 0)
                    Button(String(localized: "適用")) {
                        viewModel.applyHistory(entry)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredEntryID = isHovering ? entry.id : nil
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isHistoryPopoverPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }
}
