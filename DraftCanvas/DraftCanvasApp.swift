import SwiftUI

@main
struct DraftCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DraftCanvasViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    @StateObject private var l10n = LocalizationManager.shared
    @StateObject private var sparkleUpdater = SparkleUpdaterController()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
                .environment(\.locale, l10n.locale)
                .environmentObject(l10n)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        viewModel.refreshAccountUsageIfStale()
                    }
                }
                .onAppear {
                    appDelegate.viewModel = viewModel
                    viewModel.requestNotificationPermission()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button {
                    let info = Bundle.main.infoDictionary
                    let short = info?["CFBundleShortVersionString"] as? String ?? ""
                    let build = info?["CFBundleVersion"] as? String ?? ""
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: short,
                        .version: "build \(build)"
                    ])
                } label: {
                    Label("Draft Canvas について", systemImage: "info.circle")
                }
                Divider()
                SettingsLink()
                    .keyboardShortcut(",", modifiers: .command)
                Button {
                    sparkleUpdater.checkForUpdates()
                } label: {
                    Label("アップデートを確認…", systemImage: "square.and.arrow.down")
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
                Button {
                    ReleaseNotesWindowController.shared.present()
                } label: {
                    Label(String(localized: "リリースノート"), systemImage: "doc.text")
                }
            }
            CommandGroup(replacing: .appSettings) { }
            CommandGroup(after: .appInfo) {
                Button {
                    if let url = URL(string: "https://github.com/sponsors/5umm3r") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Support", systemImage: "heart")
                }
            }
        }

        WindowGroup("ログ", id: "logs") {
            LogWindow(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 520)

        Settings {
            SettingsView()
                .environmentObject(l10n)
                .environmentObject(viewModel)
                .environmentObject(sparkleUpdater)
                .environment(\.locale, l10n.locale)
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
