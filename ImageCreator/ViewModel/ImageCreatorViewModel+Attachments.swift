import AppKit
import Foundation
import UniformTypeIdentifiers

extension ImageCreatorViewModel {
    static let supportedImageTypes: [UTType] = [.png, .jpeg, .heic, .webP, .tiff, .bmp, .gif]

    func pickAttachmentImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.prompt = "添付"
        panel.message = "生成時の参照画像を選択してください。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachImage(from: url)
    }

    func attachImage(from url: URL) {
        do {
            let pngData = try loadAndNormalizeImage(from: url)
            let id = UUID()
            let savedURL = try projectStore.writeAttachmentData(pngData, id: id)
            let attachedImage = AttachedImage(id: id, filePath: savedURL.path, originalFileName: url.lastPathComponent)
            setAttachedImage(attachedImage)
            logs.append("参照画像を添付しました: \(url.lastPathComponent)")
        } catch {
            errorToast = "画像の読み込みに失敗しました"
            logs.append("画像添付エラー: \(error.localizedDescription)")
        }
    }

    func attachImageFromPasteboard(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            errorToast = "クリップボードの画像を処理できませんでした"
            return
        }
        do {
            let id = UUID()
            let url = try projectStore.writeAttachmentData(pngData, id: id)
            let attachedImage = AttachedImage(id: id, filePath: url.path, originalFileName: "clipboard")
            setAttachedImage(attachedImage)
            logs.append("クリップボードから画像を添付しました")
        } catch {
            errorToast = "画像の保存に失敗しました"
            logs.append("クリップボード画像保存エラー: \(error.localizedDescription)")
        }
    }

    func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        guard let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first else { return }
        attachImageFromPasteboard(image)
    }

    func removeAttachedImage() {
        if let id = selectedProjectID {
            var inputs = inputsByProject[id] ?? ProjectInputs()
            if let attached = inputs.attachedImage {
                projectStore.cleanupAttachment(id: attached.id)
            }
            inputs.attachedImage = nil
            inputsByProject[id] = inputs
        } else {
            if let attached = draftInputs.attachedImage {
                projectStore.cleanupAttachment(id: attached.id)
            }
            draftInputs.attachedImage = nil
        }
    }

    func setAttachedImage(_ attached: AttachedImage) {
        if let id = selectedProjectID {
            var inputs = inputsByProject[id] ?? ProjectInputs()
            if let editSource = inputs.editSource, editSource.isInpainting {
                projectStore.cleanupMaskFiles(id: editSource.projectItemID)
            }
            inputs.editSource = nil
            inputs.attachedImage = attached
            inputsByProject[id] = inputs
        } else {
            if let editSource = draftInputs.editSource, editSource.isInpainting {
                projectStore.cleanupMaskFiles(id: editSource.projectItemID)
            }
            draftInputs.editSource = nil
            draftInputs.attachedImage = attached
        }
    }

    func loadAndNormalizeImage(from url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else {
            throw ImageCreatorError.invalidRequest("画像を読み込めませんでした: \(url.lastPathComponent)")
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            throw ImageCreatorError.invalidRequest("画像をPNGに変換できませんでした")
        }
        return pngData
    }

    func aspectRatioFromImageData(_ data: Data) -> GenerationAspectRatio {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .square
        }
        let w = (props[kCGImagePropertyPixelWidth] as? CGFloat)
            ?? (props[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? CGFloat)
            ?? (props[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? 0
        guard w > 0, h > 0 else { return .square }
        let ratio = w / h
        return GenerationAspectRatio.allCases.min(by: { abs($0.widthOverHeight - ratio) < abs($1.widthOverHeight - ratio) }) ?? .square
    }
}
