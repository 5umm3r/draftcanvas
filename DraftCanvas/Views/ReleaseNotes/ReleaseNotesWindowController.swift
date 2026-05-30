import AppKit
import SwiftUI

final class ReleaseNotesWindowController: NSWindowController {
    static let shared = ReleaseNotesWindowController()

    private init() {
        let host = NSHostingController(rootView: ReleaseNotesView())
        let window = NSWindow(contentViewController: host)
        window.title = String(localized: "Draft Canvas リリースノート")
        window.setContentSize(NSSize(width: 480, height: 600))
        window.contentMinSize = NSSize(width: 360, height: 400)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        if !(window?.isVisible ?? false) {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
