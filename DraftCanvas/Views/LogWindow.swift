import SwiftUI

struct LogWindow: View {
    @ObservedObject var viewModel: DraftCanvasViewModel

    @State private var filterAppLog = false
    @State private var filterJobLog = false

    var body: some View {
        HSplitView {
            logPane(
                title: "App Log",
                fileKind: "applog",
                lines: Array(viewModel.logs.suffix(240)),
                isFiltered: filterAppLog,
                onToggle: { filterAppLog.toggle() }
            )
            .frame(minWidth: 360)

            logPane(
                title: "Job Log",
                fileKind: "joblog",
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
        fileKind: String,
        lines: [String],
        isFiltered: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let displayed = isFiltered ? lines.filter(isErrorLine) : lines

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    saveLogToDownloads(lines: displayed, kind: fileKind)
                } label: {
                    Label("ファイル保存", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(displayed.isEmpty)

                Button(action: onToggle) {
                    Label("エラーのみ", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(isFiltered ? .red : .secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if displayed.isEmpty {
                            Text(isFiltered ? "エラーはありません。" : "ログはまだありません。")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(displayed.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(isErrorLine(line) ? .red : .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: displayed.count) { _, _ in
                    if let last = displayed.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func saveLogToDownloads(lines: [String], kind: String) {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            viewModel.appendLog("[エラー] Downloads ディレクトリ取得失敗")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let base = "draftcanvas-\(kind)-\(stamp)"
        var url = downloads.appendingPathComponent("\(base).log")
        var counter = 1
        while fm.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent("\(base)-\(counter).log")
            counter += 1
        }
        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            viewModel.appendLog("[エラー] ログファイル保存失敗: \(error.localizedDescription)")
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
