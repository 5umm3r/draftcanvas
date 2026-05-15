import SwiftUI

@main
struct DraftCanvasApp: App {
    @StateObject private var viewModel = DraftCanvasViewModel()
    @StateObject private var l10n = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
                .environment(\.locale, l10n.locale)
                .environmentObject(l10n)
                .onAppear {
                    viewModel.requestNotificationPermission()
                }
        }
        .windowStyle(.titleBar)

        WindowGroup("ログ", id: "logs") {
            LogWindow(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 520)
    }
}
