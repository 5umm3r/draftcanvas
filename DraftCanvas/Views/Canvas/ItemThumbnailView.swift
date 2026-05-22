import SwiftUI

struct ItemThumbnailView: View {
    @ObservedObject var thumbnailStore: CanvasThumbnailStore
    let item: ProjectItem
    let originalURL: URL
    let contentMode: ContentMode
    var cardSize: CGSize = .zero
    var originalStore: CanvasOriginalImageStore? = nil
    var enableOriginalUpgrade: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var originalImage: NSImage?
    @State private var loadTask: Task<Void, Never>?

    private var needsOriginal: Bool {
        guard enableOriginalUpgrade, originalStore != nil else { return false }
        return CanvasResolutionPolicy.requiresOriginal(cardSize: cardSize, screenScale: displayScale)
    }

    var body: some View {
        ZStack {
            if let nsImage = thumbnailStore.thumbnail(for: item, originalURL: originalURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.secondary.opacity(0.08)
                    .overlay(ProgressView().controlSize(.small))
            }
            if let original = originalImage {
                Image(nsImage: original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: originalImage != nil)
        .onAppear {
            if needsOriginal { applyNeedsOriginal(true) }
        }
        .onChange(of: needsOriginal) { _, newValue in
            applyNeedsOriginal(newValue)
        }
        .onDisappear {
            loadTask?.cancel()
            originalImage = nil
        }
    }

    private func applyNeedsOriginal(_ needs: Bool) {
        loadTask?.cancel()
        guard needs else {
            originalImage = nil
            return
        }
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let store = originalStore else { return }
            if let cached = store.cached(for: originalURL) {
                withAnimation { originalImage = cached }
                return
            }
            if let img = await store.loadIfNeeded(url: originalURL) {
                withAnimation { originalImage = img }
            }
        }
    }
}
