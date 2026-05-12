import os.signpost
import Foundation

enum ImportSignposter {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.spade3.DraftCanvas",
        category: "Import"
    )
    static let signposter = OSSignposter(logHandle: log)
}
