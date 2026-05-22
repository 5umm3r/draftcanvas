import SwiftUI

struct MultiDragPreview: View {
    let items: [ProjectItem]
    let total: Int
    @ObservedObject var viewModel: DraftCanvasViewModel

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated().reversed()), id: \.element.id) { idx, item in
                ItemThumbnailView(
                    thumbnailStore: viewModel.thumbnailStore,
                    item: item,
                    originalURL: viewModel.fileURL(for: item),
                    contentMode: .fill
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                .rotationEffect(.degrees(Double(idx) * -4 + 4))
                .offset(x: CGFloat(idx) * 4, y: CGFloat(idx) * 4)
            }
        }
        .frame(width: 96, height: 96)
        .overlay(alignment: .topTrailing) {
            Text("\(total)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor))
                .overlay(Capsule().stroke(.white, lineWidth: 1))
                .padding(4)
        }
    }
}
