import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: DraftCanvasViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel else { return .terminateNow }
        let hasProtectedWork = MainActor.assumeIsolated { viewModel.hasProtectedInFlightWork }
        guard hasProtectedWork else { return .terminateNow }
        MainActor.assumeIsolated { viewModel.terminationRequested = true }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel?.saveState()
            viewModel?.stopServer()
        }
    }
}
