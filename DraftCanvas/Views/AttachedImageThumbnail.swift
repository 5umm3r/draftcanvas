import AppKit
import SwiftUI

struct AttachedImageThumbnail: View {
    let filePath: String
    var overlayPath: String? = nil
    var onTap: (() -> Void)? = nil
    let onRemove: () -> Void

    // プロンプトパネル内に置かれるためキー入力のたびに body が再評価される。
    // フルサイズ画像の同期デコードを繰り返さないよう、縮小サムネイルを
    // 一度だけ生成して保持する。マスク再編集などで同一パスのファイルが
    // 書き換わるケースは reloadKey に更新日時を含めて検知する。
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .onTapGesture { onTap?() }
                    .onHover { hovering in
                        guard onTap != nil else { return }
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .background(Color(nsColor: .windowBackgroundColor).clipShape(Circle()))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .task(id: reloadKey) {
            let overlay = overlayPath
            let file = filePath
            thumbnail = await Task.detached(priority: .userInitiated) {
                Self.loadThumbnail(overlayPath: overlay, filePath: file)
            }.value
        }
    }

    private var reloadKey: String {
        [overlayPath, filePath]
            .compactMap { $0 }
            .map { "\($0)@\(Self.modificationTimestamp(of: $0))" }
            .joined(separator: "|")
    }

    private static func modificationTimestamp(of path: String) -> TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let image = thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 80, maxHeight: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    nonisolated private static func loadThumbnail(overlayPath: String?, filePath: String) -> NSImage? {
        for path in [overlayPath, filePath].compactMap({ $0 }) {
            if let image = downsampledImage(at: path, maxPixel: 160) {
                return image
            }
        }
        return nil
    }

    // 表示サイズは最大 80x60pt のため、フルサイズを保持せず縮小版のみ生成する
    nonisolated private static func downsampledImage(at path: String, maxPixel: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

extension NSImage {
    var pixelAspectRatio: CGFloat? {
        guard let rep = representations.first(where: { $0 is NSBitmapImageRep })
                    ?? representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        return w / h
    }

    var estimatedBytes: Int {
        guard let rep = representations.first(where: { $0 is NSBitmapImageRep }) ?? representations.first else { return 0 }
        return rep.pixelsWide * rep.pixelsHigh * 4
    }
}
