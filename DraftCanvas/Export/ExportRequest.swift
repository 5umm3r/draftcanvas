import CoreGraphics
import Foundation

struct BatchExportEntry: Sendable {
    let item: ProjectItem
    let ordinal: Int
    let baseFilename: String
}

struct ExportRequest: Identifiable {
    let id = UUID()

    enum Source {
        case singleItem(ProjectItem)
        case currentJob(pngData: Data, baseFilename: String)
        case batchItems([BatchExportEntry])
    }

    let source: Source
    let originalSize: CGSize
    let hasVectorSVG: Bool
    let baseFilename: String
}
