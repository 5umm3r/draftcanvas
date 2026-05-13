import AppKit
import Foundation
import ImageIO

enum CanvasResolutionPolicy {
    static let thumbnailPixelSize: CGFloat = 512
    // 閾値付近のばたつき防止ヒステリシス
    static let upgradeRatio: CGFloat = 1.10

    static func requiresOriginal(cardSize: CGSize, screenScale: CGFloat) -> Bool {
        let longestSide = max(cardSize.width, cardSize.height)
        return longestSide * screenScale > thumbnailPixelSize * upgradeRatio
    }
}

@MainActor
final class CanvasOriginalImageStore: ObservableObject {
    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 64
        c.totalCostLimit = 256 * 1024 * 1024
        c.evictsObjectsWithDiscardedContent = true
        return c
    }()

    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func cached(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadIfNeeded(url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) {
            #if DEBUG
            CanvasMetrics.originalCacheHitCount += 1
            #endif
            return hit
        }
        if let existing = inflight[url] {
            return await existing.value
        }
        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            let opts: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldCache: true,
            ]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inflight[url] = task
        let img = await task.value
        inflight.removeValue(forKey: url)
        if let img {
            let cost: Int = img.representations
                .compactMap { $0 as? NSBitmapImageRep }
                .first
                .map { $0.pixelsWide * $0.pixelsHigh * 4 }
                ?? (8 * 1024 * 1024)
            cache.setObject(img, forKey: url as NSURL, cost: cost)
            #if DEBUG
            CanvasMetrics.originalLoadCount += 1
            CanvasMetrics.originalLoadBytesEstimate += cost
            #endif
        } else {
            #if DEBUG
            CanvasMetrics.originalCacheMissCount += 1
            #endif
        }
        return img
    }

    func evict(url: URL) {
        inflight[url]?.cancel()
        inflight.removeValue(forKey: url)
        cache.removeObject(forKey: url as NSURL)
    }

    func purgeAll() {
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        cache.removeAllObjects()
    }
}
