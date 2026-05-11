import SwiftUI

@main
struct DraftCanvasApp: App {
    @StateObject private var viewModel = DraftCanvasViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
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
