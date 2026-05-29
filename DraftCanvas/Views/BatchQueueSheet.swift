import SwiftUI

struct BatchQueueSheet: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var countPerPrompt: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("バッチ生成キュー")
                .font(.headline)

            // 入力欄
            VStack(alignment: .leading, spacing: 6) {
                Text("プロンプト（1行に1つ）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $inputText)
                    .font(.system(size: 12))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Text("各プロンプトの枚数")
                        .font(.caption)
                    Picker("", selection: $countPerPrompt) {
                        ForEach(1...8, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("キューに追加") {
                        let prompts = inputText.split(separator: "\n").map(String.init)
                        viewModel.enqueueBatch(prompts: prompts, count: countPerPrompt)
                        inputText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()

            // キュー一覧
            HStack {
                Text("キュー")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isBatchRunning {
                    Button("待機中をクリア") { viewModel.cancelBatchQueue() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.batchQueue.isEmpty {
                Text("キューが空です")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.batchQueue) { entry in
                            HStack(spacing: 8) {
                                statusIcon(entry.status)
                                Text(entry.prompt)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.count)枚")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .frame(height: 160)
            }

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private func statusIcon(_ status: BatchQueueEntry.Status) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
