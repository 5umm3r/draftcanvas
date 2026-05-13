import SwiftUI

struct FilteringProjectCreationSheet: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    var existingFiltering: FilteringProject? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var newTagInput: String = ""

    private var isEditing: Bool { existingFiltering != nil }
    private var candidateTags: [String] { viewModel.allTagsCache }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "フィルタリングプロジェクトを編集" : "フィルタリングプロジェクトを作成")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("名前").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("プロジェクト名", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("タグ条件 (AND)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("選択したすべてのタグを持つカードを表示します")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if candidateTags.isEmpty && selectedTags.isEmpty {
                    Text("まだタグがありません。カードにタグを追加してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 70, maximum: 150), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(allCandidates, id: \.self) { tag in
                                TagToggleChip(
                                    tag: tag,
                                    isSelected: selectedTags.contains(tag),
                                    onToggle: { toggleTag(tag) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }

                HStack(spacing: 6) {
                    TextField("新しいタグ条件を追加", text: $newTagInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { commitNewTag() }
                    Button("追加") { commitNewTag() }
                        .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .controlSize(.small)
                }
            }

            if !selectedTags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("選択中: \(selectedTags.sorted().joined(separator: " AND "))")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("該当カード: \(matchCount)枚")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(isEditing ? "保存" : "作成") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTags.isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let filtering = existingFiltering {
                name = filtering.name
                selectedTags = Set(filtering.tagConditions)
            }
        }
    }

    private var allCandidates: [String] {
        let base = Set(candidateTags)
        return Array(base.union(selectedTags)).sorted()
    }

    private var matchCount: Int {
        let conds = Array(selectedTags)
        return viewModel.items.filter { item in
            conds.allSatisfy { item.tags.contains($0) }
        }.count
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func commitNewTag() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTags.insert(trimmed)
        newTagInput = ""
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !selectedTags.isEmpty else { return }
        if let filtering = existingFiltering {
            viewModel.updateFilteringProject(id: filtering.id, name: trimmedName, tags: Array(selectedTags).sorted())
        } else {
            viewModel.createFilteringProject(name: trimmedName, tags: Array(selectedTags).sorted())
        }
        dismiss()
    }
}

private struct TagToggleChip: View {
    let tag: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 3) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
                Text(tag).font(.caption2).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? .blue.opacity(0.2) : Color.secondary.opacity(0.1)))
            .overlay(Capsule().stroke(isSelected ? .blue.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
