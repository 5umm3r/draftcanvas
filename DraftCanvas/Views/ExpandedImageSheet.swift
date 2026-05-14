import SwiftUI

struct ExpandedImageSheet: View {
    let item: ProjectItem
    @ObservedObject var viewModel: DraftCanvasViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Group {
                if let nsImage = viewModel.cachedImage(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ItemThumbnailView(
                        thumbnailStore: viewModel.thumbnailStore,
                        item: item,
                        originalURL: viewModel.fileURL(for: item),
                        contentMode: .fit
                    )
                }
            }
            .padding(48)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
