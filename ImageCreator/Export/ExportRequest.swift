import CoreGraphics
import Foundation

struct ExportRequest: Identifiable {
    let id = UUID()

    enum Source {
        case singleItem(ProjectItem)
        case currentJob(pngData: Data, baseFilename: String)
    }

    let source: Source
    let originalSize: CGSize
    let hasVectorSVG: Bool
    let baseFilename: String
}
