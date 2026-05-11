import SwiftUI

struct TagEditorRow: View {
    let itemID: UUID
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var tagInput = ""
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    private var currentTags: [String] {
        viewModel.items.first(where: { $0.id == itemID })?.tags ?? []
    }

    private var suggestions: [String] {
        let existing = Set(currentTags)
        if tagInput.isEmpty {
            return viewModel.allTags.filter { !existing.contains($0) }
        }
        return viewModel.allTags.filter {
            $0.localizedCaseInsensitiveContains(tagInput) && !existing.contains($0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("タグ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !currentTags.isEmpty {
                TagChipGrid(tags: currentTags) { tag in
                    viewModel.removeTag(tag, from: itemID)
                }
            }

            HStack(spacing: 4) {
                TextField("タグを追加", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isFocused)
                    .onSubmit { commitTag() }
                    .onChange(of: isFocused) { _, focused in
                        showSuggestions = focused
                    }
                if !tagInput.isEmpty {
                    Button { commitTag() } label: {
                        Image(systemName: "return").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            if showSuggestions && !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions.prefix(6), id: \.self) { tag in
                            Button {
                                viewModel.addTag(tag, to: itemID)
                                tagInput = ""
                            } label: {
                                Text(tag)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 96)
                .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))
            }
        }
    }

    private func commitTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addTag(trimmed, to: itemID)
        tagInput = ""
    }
}

private struct TagChipGrid: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text(tag)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 120)
                        Button { onRemove(tag) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.blue.opacity(0.12)))
                    .overlay(Capsule().stroke(.blue.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }
}
