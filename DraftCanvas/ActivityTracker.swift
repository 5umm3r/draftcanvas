import Foundation

@MainActor
final class ActivityTracker {
    private var activityToken: NSObjectProtocol?
    private var count = 0

    func begin() {
        count += 1
        if count == 1 {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Image generation or export in progress"
            )
        }
    }

    func end() {
        guard count > 0 else { return }
        count -= 1
        if count == 0, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    func endAll() {
        count = 0
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
