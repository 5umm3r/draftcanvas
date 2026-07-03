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
            // saveState はデバウンスされるため、終了時は即時同期保存を使う
            viewModel?.saveStateNow()
            viewModel?.stopServer()
        }
    }
}
