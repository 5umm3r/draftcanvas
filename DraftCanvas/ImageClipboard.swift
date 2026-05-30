import AppKit

enum ImageClipboard {
    /// 画像を NSPasteboard にコピーする。
    /// NSImage と PNG Data の両方を書き込み、透明チャンネルを保持する。
    static func copy(imageData: Data, image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pb.setData(imageData, forType: .png)
    }
}
