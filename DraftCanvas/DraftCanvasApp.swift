import SwiftUI

@main
struct DraftCanvasApp: App {
    @StateObject private var viewModel = DraftCanvasViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
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
                    if let warning = EntitlementGate.shared.consumeTrialWarning() {
                        viewModel.errorToast = warning
                    }
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
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button {
                    sparkleUpdater.checkForUpdates()
                } label: {
                    Label("アップデートを確認…", systemImage: "square.and.arrow.down")
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
                trialStatusMenuItem
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
    }
}


private extension DraftCanvasApp {
    @ViewBuilder
    var trialStatusMenuItem: some View {
        switch gate.status {
        case .licensed:
            EmptyView()
        case .trial(let daysLeft):
            Button {
                gate.showLicenseSheet = true
            } label: {
                if daysLeft <= 3 {
                    Label("トライアル: 残 \(daysLeft) 日",
                          systemImage: "exclamationmark.triangle.fill")
                } else {
                    Text("トライアル: 残 \(daysLeft) 日")
                }
            }
        case .expired:
            Button {
                gate.showLicenseSheet = true
            } label: {
                Label("トライアル期限切れ",
                      systemImage: "exclamationmark.octagon.fill")
            }
        }
    }
}
