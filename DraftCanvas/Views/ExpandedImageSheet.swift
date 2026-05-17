import SwiftUI
import AppKit

struct ExpandedImageSheet: View {
    let items: [ProjectItem]
    @ObservedObject var viewModel: DraftCanvasViewModel
    let onDismiss: () -> Void

    @State private var currentItemID: ProjectItem.ID
    @State private var keyMonitor: Any?

    init(item: ProjectItem, items: [ProjectItem], viewModel: DraftCanvasViewModel, onDismiss: @escaping () -> Void) {
        self.items = items
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self._currentItemID = State(initialValue: item.id)
    }

    private var currentItem: ProjectItem? { items.first(where: { $0.id == currentItemID }) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if let item = currentItem {
                imageContent(for: item)
                    .padding(48)
                    .allowsHitTesting(false)
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
                    HStack(spacing: 8) {
                        Button(action: goPrevious) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        let displayIndex = items.firstIndex(where: { $0.id == currentItemID }).map { $0 + 1 } ?? 0
                        Text("\(displayIndex) / \(items.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())

                        Button(action: goNext) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: items) { _ in
            if !items.contains(where: { $0.id == currentItemID }) {
                onDismiss()
            }
        }
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
        guard !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == currentItemID }) else { return }
        currentItemID = items[(idx + 1) % items.count].id
    }

    private func goPrevious() {
        guard !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == currentItemID }) else { return }
        currentItemID = items[(idx - 1 + items.count) % items.count].id
    }
}
