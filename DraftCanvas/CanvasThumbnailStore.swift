import AppKit
import Foundation
import ImageIO

final class CanvasThumbnailStore: ObservableObject, @unchecked Sendable {
    let thumbsDirectory: URL
    private let maxPixelSize: CGFloat = 512
    @Published private(set) var version: Int = 0
    private let memoryCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 256
        c.totalCostLimit = 128 * 1024 * 1024
        return c
    }()

    init(itemsDirectory: URL) {
        thumbsDirectory = itemsDirectory.appendingPathComponent(".thumbs", isDirectory: true)
    }

    func thumbnailURL(for item: ProjectItem) -> URL {
        let ext = (item.isBackgroundRemoved || item.hasSVG) ? "png" : "jpg"
        return thumbsDirectory.appendingPathComponent("\(item.id.uuidString).\(ext)")
    }

    // メインスレッドから呼ぶ。ヒット→即返却。ミス→nil＋非同期生成kick
    func thumbnail(for item: ProjectItem, originalURL: URL) -> NSImage? {
        let url = thumbnailURL(for: item)
        let key = url as NSURL
        if let cached = memoryCache.object(forKey: key) { return cached }
        if let img = loadThumbnailFromDisk(url: url) {
            memoryCache.setObject(img, forKey: key, cost: 1024 * 1024)
            return img
        }
        let store = self
        Task.detached(priority: .utility) {
            store.generateAndSave(from: originalURL, item: item)
            await MainActor.run { store.version &+= 1 }
        }
        return nil
    }

    private func loadThumbnailFromDisk(url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true,
        ]
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // 生成/インポート直後に呼ぶ（Data バージョン）
    func writeThumbnail(from data: Data, item: ProjectItem) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        generateAndSave(source: src, item: item)
    }

    // 生成/インポート直後に呼ぶ（URL バージョン）
    func writeThumbnail(from url: URL, item: ProjectItem) {
        generateAndSave(from: url, item: item)
    }

    func invalidate() {
        version &+= 1
    }

    func deleteThumbnail(for item: ProjectItem) {
        let url = thumbnailURL(for: item)
        memoryCache.removeObject(forKey: url as NSURL)
        try? FileManager.default.removeItem(at: url)
    }

    func backfillMissing(items: [ProjectItem], originalURL: (ProjectItem) -> URL) {
        let missing: [(ProjectItem, URL)] = items.compactMap { item in
            let thumbURL = thumbnailURL(for: item)
            guard !FileManager.default.fileExists(atPath: thumbURL.path) else { return nil }
            let orig = originalURL(item)
            guard FileManager.default.fileExists(atPath: orig.path) else { return nil }
            return (item, orig)
        }
        guard !missing.isEmpty else { return }
        let store = self
        Task.detached(priority: .utility) {
            var count = 0
            for (item, url) in missing {
                store.generateAndSave(from: url, item: item)
                count += 1
                if count % 2 == 0 {
                    await Task.yield()
                    await MainActor.run { store.version &+= 1 }
                }
            }
            await MainActor.run { store.version &+= 1 }
        }
    }

    private func generateAndSave(from url: URL, item: ProjectItem) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        generateAndSave(source: src, item: item)
    }

    private func generateAndSave(source: CGImageSource, item: ProjectItem) {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data: Data?
        if item.isBackgroundRemoved || item.hasSVG {
            data = rep.representation(using: .png, properties: [:])
        } else {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: 0.85)])
        }
        guard let thumbData = data else { return }
        let dest = thumbnailURL(for: item)
        try? FileManager.default.createDirectory(at: thumbsDirectory, withIntermediateDirectories: true)
        try? thumbData.write(to: dest, options: .atomic)
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memoryCache.setObject(img, forKey: dest as NSURL, cost: 1024 * 1024)
    }
}
