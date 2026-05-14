import SwiftUI
import os.signpost

struct ItemDetailPopover: View {
    let item: ProjectItem
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var isRevisedExpanded = false
    @State private var isConfirmingDelete = false

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

            Divider()
                .padding(.vertical, 2)

            PopoverButton(systemImage: "wand.and.stars", title: "再編集",
                          action: {
                              viewModel.edit(item: item)
                              viewModel.selectedItemID = nil
                          },
                          costLevel: viewModel.selectedModelCostLevel)

            PopoverButton(systemImage: "paintbrush.pointed", title: "マスクして編集",
                          action: {
                              viewModel.inpaint(item: item)
                              viewModel.selectedItemID = nil
                          },
                          costLevel: viewModel.itemActionCostLevel)

            PopoverButton(systemImage: "eraser", title: "マスクして除去",
                          action: {
                              viewModel.maskRemove(item: item)
                              viewModel.selectedItemID = nil
                          },
                          costLevel: viewModel.itemActionCostLevel)

            PopoverButton(
                systemImage: "scissors",
                title: "背景を除去",
                action: {
                    viewModel.startBackgroundRemoval(item: item)
                    viewModel.selectedItemID = nil
                },
                isDisabled: item.isBackgroundRemoved,
                disabledReason: item.isBackgroundRemoved ? "背景除去済み" : nil
            )

            PopoverButton(systemImage: "square.3.layers.3d", title: "素材分解") {
                viewModel.startMaterialExtraction(item: item)
                viewModel.selectedItemID = nil
            }

            PopoverButton(
                systemImage: "pencil.and.outline",
                title: "ベクター化",
                action: {
                    viewModel.vectorize(item: item)
                    viewModel.selectedItemID = nil
                },
                isDisabled: item.hasSVG,
                disabledReason: item.hasSVG ? "ベクター化済み" : nil
            )

            PopoverButton(systemImage: "doc.on.doc", title: "複製") {
                viewModel.duplicateItem(item)
                viewModel.selectedItemID = nil
            }

            PopoverButton(systemImage: "folder", title: "Finderで表示") {
                viewModel.reveal(item: item)
            }

            PopoverButton(systemImage: "trash", title: "削除") {
                isConfirmingDelete = true
            }
            .foregroundStyle(.red)

            Divider()
                .padding(.vertical, 4)

            Button {
                viewModel.exportItem(item)
            } label: {
                Label("エクスポート", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(width: 300, height: 650)
        .alert("画像を削除しますか？", isPresented: $isConfirmingDelete) {
            Button("削除", role: .destructive) {
                viewModel.deleteItem(item)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
    }
}
