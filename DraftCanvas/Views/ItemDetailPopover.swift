import SwiftUI
import os.signpost

struct ItemDetailPopover: View {
    let item: ProjectItem
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var isRevisedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(width: 0, height: 0).onAppear {
                os_signpost(.end, log: PopoverSignposter.log, name: "ItemDetailPopover")
            }
            DetailRow(
                label: "Prompt",
                value: item.prompt,
                trailing: item.prompt.isEmpty ? nil : AnyView(PromptCopyButton(prompt: item.prompt))
            )
            DetailRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let revisedPrompt = item.revisedPrompt {
                DisclosureGroup(isExpanded: $isRevisedExpanded) {
                    DetailRow(label: "", value: revisedPrompt)
                        .padding(.top, 4)
                } label: {
                    Text("Revised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = item.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            TagEditorRow(itemID: item.id, viewModel: viewModel)

            Divider().padding(.top, 4)
            Button {
                viewModel.reveal(item: item)
            } label: {
                Label("Finderで表示", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 300)
    }
}
