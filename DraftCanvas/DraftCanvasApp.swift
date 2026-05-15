import SwiftUI

@main
struct DraftCanvasApp: App {
    @StateObject private var viewModel = DraftCanvasViewModel()
    @StateObject private var l10n = LocalizationManager.shared
    @StateObject private var sparkleUpdater = SparkleUpdaterController()
    @StateObject private var gate = EntitlementGate.shared

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
                .environment(\.locale, l10n.locale)
                .environmentObject(l10n)
                .onAppear {
                    viewModel.requestNotificationPermission()
                    EntitlementGate.shared.evaluate()
                }
                .sheet(isPresented: $gate.showLicensePrompt) {
                    TrialExpiredView()
                }
                .sheet(isPresented: $gate.showLicenseSheet) {
                    LicenseSheet()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("アップデートを確認…")) {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
                if gate.status != .licensed {
                    Button(L("ライセンスを有効化…")) {
                        gate.showLicenseSheet = true
                    }
                }
                Button(L("ライセンス…")) {
                    NotificationCenter.default.post(name: .openLicensesWindow, object: nil)
                }
            }
        }

        WindowGroup("ログ", id: "logs") {
            LogWindow(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 520)

        WindowGroup(L("ライセンス"), id: "licenses") {
            LicensesWindow()
                .environmentObject(l10n)
                .environment(\.locale, l10n.locale)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 520)
    }
}

extension Notification.Name {
    static let openLicensesWindow = Notification.Name("openLicensesWindow")
}
