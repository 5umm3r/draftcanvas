import Foundation
import AppKit
import ImageIO

enum ICloudImageLoaderError: Error, Equatable {
    case downloadTimeout
    case cancelled
    case fileNotFound
}

/// iCloud / ローカル両対応の async ファイル読込ヘルパー。
///
/// - 未 DL の iCloud ファイルは `startDownloadingUbiquitousItem` を呼び、
///   `ubiquitousItemDownloadingStatusKey` をポーリングして DL 完了を待つ。
/// - iCloud 配下では `NSFileCoordinator` で協調読込。
actor ICloudImageLoader {
    private let pollInterval: Duration
    private let timeout: Duration

    init(pollInterval: Duration = .milliseconds(150), timeout: Duration = .seconds(60)) {
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    func loadData(at url: URL, syncMonitor: ICloudSyncMonitor?) async throws -> Data {
        if let monitor = syncMonitor {
            try await ensureDownloaded(url: url, monitor: monitor)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ICloudImageLoaderError.fileNotFound
        }
        return try await coordinatedRead(url: url, isUbiquitous: syncMonitor != nil)
    }

    func loadImage(at url: URL, syncMonitor: ICloudSyncMonitor?) async throws -> NSImage? {
        let data = try await loadData(at: url, syncMonitor: syncMonitor)
        return NSImage(data: data)
    }

    func waitForDownload(at url: URL, syncMonitor: ICloudSyncMonitor) async throws {
        try await ensureDownloaded(url: url, monitor: syncMonitor)
    }

    private func ensureDownloaded(url: URL, monitor: ICloudSyncMonitor) async throws {
        let isDownloaded = await MainActor.run { monitor.isDownloaded(url: url) }
        if isDownloaded { return }

        await MainActor.run { monitor.requestDownload(for: url) }

        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            try Task.checkCancellation()
            let done = await MainActor.run { monitor.isDownloaded(url: url) }
            if done { return }
            try await Task.sleep(for: pollInterval)
        }
        throw ICloudImageLoaderError.downloadTimeout
    }

    private func coordinatedRead(url: URL, isUbiquitous: Bool) async throws -> Data {
        if !isUbiquitous {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        return try await withCheckedThrowingContinuation { cont in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            // アクセサ実行済みかつ coordError も設定されるケースで
            // continuation を二重 resume しないようフラグで防護する
            var didResume = false
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { actualURL in
                didResume = true
                do {
                    let data = try Data(contentsOf: actualURL, options: [.mappedIfSafe])
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
            if !didResume {
                cont.resume(throwing: coordError ?? CocoaError(.fileReadUnknown))
            }
        }
    }
}
