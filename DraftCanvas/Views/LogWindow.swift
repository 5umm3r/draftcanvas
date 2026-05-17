import SwiftUI

struct LogWindow: View {
    @ObservedObject var viewModel: DraftCanvasViewModel

    @State private var filterAppLog = false
    @State private var filterJobLog = false

    var body: some View {
        HSplitView {
            logPane(
                title: "App Log",
                lines: Array(viewModel.logs.suffix(240)),
                isFiltered: filterAppLog,
                onToggle: { filterAppLog.toggle() }
            )
            .frame(minWidth: 360)

            logPane(
                title: "Job Log",
                lines: Array((viewModel.selectedJob?.logs ?? []).suffix(500)),
                isFiltered: filterJobLog,
                onToggle: { filterJobLog.toggle() }
            )
            .frame(minWidth: 320)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 420)
    }

    private func logPane(
        title: String,
        lines: [String],
        isFiltered: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onToggle) {
                    Label("エラーのみ", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(isFiltered ? .red : .secondary)
            }

            let displayed = isFiltered ? lines.filter(isErrorLine) : lines

            ScrollView {
                Group {
                    if displayed.isEmpty {
                        Text(isFiltered ? "エラーはありません。" : "ログはまだありません。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(displayed.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(isErrorLine(line) ? .red : .secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func isErrorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("error") ||
               lower.contains("エラー") ||
               line.contains("[警告]") ||
               lower.contains("warn") ||
               lower.contains("failed") ||
               lower.contains("失敗") ||
               lower.contains("timeout") ||
               lower.contains("タイムアウト")
    }
}
