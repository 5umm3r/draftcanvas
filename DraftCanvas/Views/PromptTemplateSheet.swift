import SwiftUI

struct PromptTemplateSheet: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingID: UUID?
    @State private var name: String = ""
    @State private var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("プロンプトテンプレート")
                .font(.headline)

            // 一覧
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.promptTemplates) { template in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(template.name)
                                        .font(.system(size: 13, weight: .medium))
                                    if template.isBuiltIn {
                                        Text("プリセット")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    }
                                }
                                Text(template.prompt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if !template.isBuiltIn {
                                Button {
                                    editingID = template.id
                                    name = template.name
                                    prompt = template.prompt
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    viewModel.deleteTemplate(id: template.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            .frame(height: 220)

            Divider()

            // 作成/編集フォーム
            VStack(alignment: .leading, spacing: 8) {
                Text(editingID == nil ? "新規テンプレート" : "テンプレートを編集")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("名前", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("プロンプト", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    if editingID != nil {
                        Button("新規に切替") { resetForm() }
                    }
                    Spacer()
                    Button(editingID == nil ? "追加" : "保存") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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

    private func resetForm() {
        editingID = nil
        name = ""
        prompt = ""
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }
        if let id = editingID {
            viewModel.updateTemplate(PromptTemplate(id: id, name: trimmedName, prompt: trimmedPrompt))
        } else {
            viewModel.saveTemplate(PromptTemplate(name: trimmedName, prompt: trimmedPrompt))
        }
        resetForm()
    }
}
