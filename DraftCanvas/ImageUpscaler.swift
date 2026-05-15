import Foundation
import AppKit

struct UpscalePreviewPayload: Identifiable {
    let id = UUID()
    let originalItem: ProjectItem
    let originalImageData: Data
    let upscaledImageData: Data
    let jobLogs: [String]
}

enum UpscaleApplyMode {
    case overwrite
    case addAsNew
    case discard
}
