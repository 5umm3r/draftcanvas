import SwiftUI
import os.signpost

struct ItemDetailPopover: View {
    let item: ProjectItem
    @ObservedObject var viewModel: DraftCanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(width: 0, height: 0).onAppear {
                os_signpost(.end, log: PopoverSignposter.log, name: "ItemDetailPopover")
            }

            if let sketchPath = item.sketchSourcePath,
               let nsImage = NSImage(contentsOfFile: sketchPath) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ラフ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 264, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }

            DetailRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

            DetailRow(
                label: "Prompt",
                value: item.prompt,
                trailing: item.prompt.isEmpty ? nil : AnyView(PromptCopyButton(prompt: item.prompt)),
                lineLimit: nil
            )

            if let revisedPrompt = item.revisedPrompt {
                DetailRow(
                    label: "Revised",
                    value: revisedPrompt,
                    trailing: AnyView(PromptCopyButton(prompt: revisedPrompt)),
                    lineLimit: nil
                )
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
