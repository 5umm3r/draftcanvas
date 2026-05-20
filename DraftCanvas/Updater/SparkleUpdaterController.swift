import Sparkle
import Combine

@MainActor
final class SparkleUpdaterController: NSObject, ObservableObject {
    private var updaterController: SPUStandardUpdaterController!
    private var cancellables: Set<AnyCancellable> = []

    var updater: SPUUpdater { updaterController.updater }

    @Published private(set) var canCheckForUpdates: Bool = false

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension SparkleUpdaterController: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        "https://github.com/5umm3r/draftcanvas-releases/releases/latest/download/appcast.xml"
    }
}
