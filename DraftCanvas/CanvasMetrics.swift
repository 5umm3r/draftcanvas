#if DEBUG
import Darwin
import Foundation

@MainActor
enum CanvasMetrics {
    static var imageLoadCount = 0
    static var imageLoadBytesEstimate: Int = 0

    static var residentMemoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Int(info.resident_size) / 1_048_576
    }

    static func logSummary(tag: String) -> String {
        "[CanvasMetrics:\(tag)] loads=\(imageLoadCount) estimatedMB=\(imageLoadBytesEstimate / 1_048_576) residentMB=\(residentMemoryMB)"
    }

    static func reset() {
        imageLoadCount = 0
        imageLoadBytesEstimate = 0
    }
}
#endif
