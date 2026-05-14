import SwiftUI

struct LogWindow: View {
    @ObservedObject var viewModel: DraftCanvasViewModel

    var body: some View {
        HSplitView {
            logPane(title: "App Log", lines: Array(viewModel.logs.suffix(240)))
                .frame(minWidth: 360)

            logPane(title: "Job Log", lines: viewModel.selectedJob?.logs ?? [])
                .frame(minWidth: 320)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 420)
    }

    private func logPane(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ScrollView {
                Group {
                    if lines.isEmpty {
                        Text("ログはまだありません。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
