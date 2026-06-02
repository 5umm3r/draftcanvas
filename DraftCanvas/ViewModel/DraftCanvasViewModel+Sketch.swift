import AppKit
import Foundation

struct SketchEditorTarget: Identifiable {
    let id: UUID
    let aspectRatio: GenerationAspectRatio
    let existingAttachment: AttachedImage?

    init(aspectRatio: GenerationAspectRatio, existingAttachment: AttachedImage? = nil) {
        self.id = UUID()
        self.aspectRatio = aspectRatio
        self.existingAttachment = existingAttachment
    }

    var canvasPixelSize: CGSize {
        let ratio = aspectRatio.widthOverHeight
        if ratio >= 1 {
            return CGSize(width: 1024, height: (1024 / ratio).rounded())
        } else {
            return CGSize(width: (1024 * ratio).rounded(), height: 1024)
        }
    }

    var initialStrokes: [SketchStroke] { [] }
}

extension DraftCanvasViewModel {

    func openSketchEditor() {
        let aspectRatio = currentInputs.aspectRatio
        sketchEditorTarget = SketchEditorTarget(aspectRatio: aspectRatio)
    }

    func openSketchEditorForReedit(_ attached: AttachedImage) {
        guard attached.kind == .sketch else { return }
        let aspectRatio = currentInputs.aspectRatio
        sketchEditorTarget = SketchEditorTarget(aspectRatio: aspectRatio, existingAttachment: attached)
    }

    func applySketch(strokes: [SketchStroke], canvasPixelSize: CGSize, existingID: UUID?) {
        guard let pngData = SketchCompositor.renderPNG(from: strokes, canvasSize: canvasPixelSize) else {
            showError("ラフ画像の生成に失敗しました")
            return
        }

        do {
            let attachID = existingID ?? UUID()

            if let existingID {
                projectStore.cleanupAttachment(id: existingID)
            }

            let savedURL = try projectStore.writeAttachmentData(resizedForCodex(pngData), id: attachID)
            let strokesURL = try projectStore.writeSketchStrokesData(strokes, id: attachID)

            let attached = AttachedImage(
                id: attachID,
                filePath: savedURL.path,
                originalFileName: nil,
                kind: .sketch,
                sketchStrokesFilePath: strokesURL.path,
                canvasPixelSize: canvasPixelSize
            )
            setAttachedImage(attached)
            logs.append("ラフを添付しました")
        } catch {
            showError("ラフ画像の保存に失敗しました")
            logs.append("ラフ保存エラー: \(error.localizedDescription)")
        }
    }

    func loadSketchStrokes(for attached: AttachedImage) -> [SketchStroke] {
        projectStore.readSketchStrokesData(id: attached.id) ?? []
    }

    // 512px以下にダウンスケール → 4タイル(765tokens)→1タイル(255tokens)
    private func resizedForCodex(_ data: Data, maxDimension: CGFloat = 512) -> Data {
        guard let image = NSImage(data: data) else { return data }
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        guard scale < 1.0 else { return data }
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return data }
        return rep.representation(using: .png, properties: [:]) ?? data
    }
}
