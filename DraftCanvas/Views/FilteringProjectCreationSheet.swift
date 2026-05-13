import SwiftUI

struct FilteringProjectCreationSheet: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    var existingFiltering: FilteringProject? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var searchQuery: String = ""

    private var isEditing: Bool { existingFiltering != nil }

    private var matchCount: Int {
        viewModel.itemsMatching(searchQuery: searchQuery).count
    }

    private var queryTokens: Set<String> {
        Set(searchQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

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
                Text("検索クエリ（スペース区切り AND 部分一致）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例: 猫 夕日", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("該当カード: \(matchCount)枚")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.allTagsCache.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("既存タグから追加")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 60, maximum: 140), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(viewModel.allTagsCache, id: \.self) { tag in
                                TagToggleChip(
                                    tag: tag,
                                    isSelected: queryTokens.contains(tag),
                                    onToggle: { toggleTag(tag) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(isEditing ? "保存" : "作成") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let filtering = existingFiltering {
                name = filtering.name
                searchQuery = filtering.searchQuery
            }
        }
    }

    private func toggleTag(_ tag: String) {
        var tokens = searchQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if let idx = tokens.firstIndex(of: tag) {
            tokens.remove(at: idx)
        } else {
            tokens.append(tag)
        }
        searchQuery = tokens.joined(separator: " ")
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if let filtering = existingFiltering {
            viewModel.updateFilteringProject(id: filtering.id, name: trimmedName, searchQuery: searchQuery)
        } else {
            viewModel.createFilteringProject(name: trimmedName, searchQuery: searchQuery)
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
