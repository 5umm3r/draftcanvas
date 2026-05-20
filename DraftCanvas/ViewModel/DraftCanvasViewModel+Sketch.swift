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
            errorToast = String(localized: "ラフ画像の生成に失敗しました")
            return
        }

        do {
            let attachID = existingID ?? UUID()

            if let existingID {
                projectStore.cleanupAttachment(id: existingID)
            }

            let savedURL = try projectStore.writeAttachmentData(pngData, id: attachID)
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
            errorToast = String(localized: "ラフ画像の保存に失敗しました")
            logs.append("ラフ保存エラー: \(error.localizedDescription)")
        }
    }

    func loadSketchStrokes(for attached: AttachedImage) -> [SketchStroke] {
        projectStore.readSketchStrokesData(id: attached.id) ?? []
    }
}
