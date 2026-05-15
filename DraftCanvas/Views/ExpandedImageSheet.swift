import SwiftUI
import AppKit

struct ExpandedImageSheet: View {
    let items: [ProjectItem]
    @ObservedObject var viewModel: DraftCanvasViewModel
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var keyMonitor: Any?

    init(item: ProjectItem, items: [ProjectItem], viewModel: DraftCanvasViewModel, onDismiss: @escaping () -> Void) {
        self.items = items
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: items.firstIndex(where: { $0.id == item.id }) ?? 0)
    }

    private var currentItem: ProjectItem { items[currentIndex] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            imageContent(for: currentItem)
                .padding(48)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if items.count > 1 {
                HStack {
                    Button(action: goPrevious) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)

                    Spacer()

                    Button(action: goNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .keyboardShortcut(.escape, modifiers: [])

            if items.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 123: goPrevious(); return nil  // ←
                case 124: goNext(); return nil       // →
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private func imageContent(for item: ProjectItem) -> some View {
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

    private func goNext() {
        currentIndex = (currentIndex + 1) % items.count
    }

    private func goPrevious() {
        currentIndex = (currentIndex - 1 + items.count) % items.count
    }
}
