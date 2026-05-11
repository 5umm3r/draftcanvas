import AppKit
import SwiftUI

struct AttachedImageThumbnail: View {
    let filePath: String
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image = NSImage(contentsOfFile: filePath) {
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
}
