import AppKit
import Foundation
import UniformTypeIdentifiers

extension DraftCanvasViewModel {
    static let supportedImageTypes: [UTType] = [.png, .jpeg, .heic, .webP, .tiff, .bmp, .gif]

    func pickAttachmentImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.prompt = L("添付")
        panel.message = L("生成時の参照画像を選択してください。")
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
            errorToast = L("画像の読み込みに失敗しました")
            logs.append("画像添付エラー: \(error.localizedDescription)")
        }
    }

    func attachImageFromPasteboard(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            errorToast = L("クリップボードの画像を処理できませんでした")
            return
        }
        do {
            let id = UUID()
            let url = try projectStore.writeAttachmentData(pngData, id: id)
            let attachedImage = AttachedImage(id: id, filePath: url.path, originalFileName: "clipboard")
            setAttachedImage(attachedImage)
            logs.append("クリップボードから画像を添付しました")
        } catch {
            errorToast = L("画像の保存に失敗しました")
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

    struct DecodedImportImage {
        let data: Data
        let fileExtension: String
        let aspectRatio: GenerationAspectRatio
        let actualAspectRatio: CGFloat?
    }

    nonisolated func decodeImportImage(from url: URL) throws -> DecodedImportImage {
        let raw = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let source = CGImageSourceCreateWithData(raw as CFData, nil) else {
            throw DraftCanvasError.invalidRequest(L("画像を読み込めませんでした: \(url.lastPathComponent)"))
        }
        let aspect = aspectRatioFromImageSource(source)
        let actualRatio = pixelAspectRatioFromImageSource(source)
        let typeID = CGImageSourceGetType(source) as String?
        let passthroughExt: String? = {
            switch typeID {
            case "public.png": return "png"
            case "public.jpeg": return "jpg"
            case "public.heic", "public.heif": return "heic"
            default: return nil
            }
        }()
        if let ext = passthroughExt {
            return DecodedImportImage(data: raw, fileExtension: ext, aspectRatio: aspect, actualAspectRatio: actualRatio)
        }
        // フォールバック: CGImageDestination で PNG 化（AppKit 経由しない）
        let png = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
            throw DraftCanvasError.invalidRequest(L("画像をPNGに変換できませんでした"))
        }
        CGImageDestinationAddImageFromSource(dest, source, 0, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw DraftCanvasError.invalidRequest(L("画像をPNGに変換できませんでした"))
        }
        return DecodedImportImage(data: png as Data, fileExtension: "png", aspectRatio: aspect, actualAspectRatio: actualRatio)
    }

    nonisolated func aspectRatioFromImageSource(_ source: CGImageSource) -> GenerationAspectRatio {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .square
        }
        let w = (props[kCGImagePropertyPixelWidth] as? CGFloat)
            ?? (props[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? CGFloat)
            ?? (props[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? 0
        guard w > 0, h > 0 else { return .square }
        let ratio = w / h
        return GenerationAspectRatio.allCases.filter { $0 != .auto }.min(by: { abs($0.widthOverHeight - ratio) < abs($1.widthOverHeight - ratio) }) ?? .square
    }

    nonisolated func pixelAspectRatioFromImageSource(_ source: CGImageSource) -> CGFloat? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = (props[kCGImagePropertyPixelWidth] as? CGFloat)
            ?? (props[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? CGFloat)
            ?? (props[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? 0
        guard w > 0, h > 0 else { return nil }
        return w / h
    }

    nonisolated func loadAndNormalizeImage(from url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else {
            throw DraftCanvasError.invalidRequest(L("画像を読み込めませんでした: \(url.lastPathComponent)"))
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            throw DraftCanvasError.invalidRequest(L("画像をPNGに変換できませんでした"))
        }
        return pngData
    }

    nonisolated func aspectRatioFromImageData(_ data: Data) -> GenerationAspectRatio {
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
        return GenerationAspectRatio.allCases.filter { $0 != .auto }.min(by: { abs($0.widthOverHeight - ratio) < abs($1.widthOverHeight - ratio) }) ?? .square
    }

    nonisolated func pixelAspectRatioFromImageData(_ data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelAspectRatioFromImageSource(source)
    }
}
