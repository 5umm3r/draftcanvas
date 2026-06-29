import SwiftUI

struct ItemThumbnailView: View {
    let thumbnailStore: CanvasThumbnailStore
    let item: ProjectItem
    let originalURL: URL
    let contentMode: ContentMode
    var cardSize: CGSize = .zero
    var originalStore: CanvasOriginalImageStore? = nil
    var syncMonitor: ICloudSyncMonitor? = nil
    var enableOriginalUpgrade: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: NSImage?
    @State private var originalImage: NSImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var isOriginalDownloading: Bool = false

    private var needsOriginal: Bool {
        guard enableOriginalUpgrade, originalStore != nil else { return false }
        return CanvasResolutionPolicy.requiresOriginal(cardSize: cardSize, screenScale: displayScale)
    }

    var body: some View {
        ZStack {
            if let nsImage = thumbnailImage {
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
            if isOriginalDownloading, originalImage == nil, needsOriginal {
                Color.black.opacity(0.15)
                ProgressView()
                    .controlSize(.small)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: originalImage != nil)
        .onAppear {
            thumbnailImage = thumbnailStore.thumbnail(for: item, originalURL: originalURL)
            if needsOriginal { applyNeedsOriginal(true) }
        }
        .onReceive(thumbnailStore.thumbnailUpdated) { updatedID in
            guard updatedID == item.id else { return }
            thumbnailImage = thumbnailStore.thumbnailFromCache(for: item)
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
        isOriginalDownloading = false
        guard needs else {
            originalImage = nil
            return
        }
        loadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let store = originalStore else { return }
            if let cached = store.cached(for: originalURL) {
                withAnimation { originalImage = cached }
                return
            }
            if let monitor = syncMonitor, !monitor.isDownloaded(url: originalURL) {
                isOriginalDownloading = true
            }
            let img = await store.loadIfNeeded(url: originalURL, syncMonitor: syncMonitor)
            isOriginalDownloading = false
            if let img {
                withAnimation { originalImage = img }
            }
        }
    }
}
