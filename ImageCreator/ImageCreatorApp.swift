import SwiftUI

@main
struct ImageCreatorApp: App {
    @StateObject private var viewModel = ImageCreatorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.titleBar)

        WindowGroup("ログ", id: "logs") {
            LogWindow(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 520)
    }
}
