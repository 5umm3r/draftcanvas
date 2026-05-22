import Foundation
import CoreGraphics

// MARK: - AttachedImage

struct AttachedImage: Equatable {
    let id: UUID
    let filePath: String
    let originalFileName: String?
    var kind: AttachmentKind
    var sketchStrokesFilePath: String?
    var canvasPixelSize: CGSize?

    init(
        id: UUID = UUID(),
        filePath: String,
        originalFileName: String? = nil,
        kind: AttachmentKind = .regular,
        sketchStrokesFilePath: String? = nil,
        canvasPixelSize: CGSize? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.originalFileName = originalFileName
        self.kind = kind
        self.sketchStrokesFilePath = sketchStrokesFilePath
        self.canvasPixelSize = canvasPixelSize
    }
}
