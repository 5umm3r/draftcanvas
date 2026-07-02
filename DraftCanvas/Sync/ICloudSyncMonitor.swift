import Foundation
import Combine
import Network

enum ICloudSyncStatus: Equatable {
    case disabled
    case synced
    case syncing(pending: Int)
    case error(String)
    case offline
}

@MainActor
final class ICloudSyncMonitor: ObservableObject {
    @Published private(set) var syncStatus: ICloudSyncStatus = .disabled
    @Published private(set) var totalDataSize: Int64 = 0
    @Published private(set) var totalItemCount: Int = 0
    @Published private(set) var downloadingItemIDs: Set<UUID> = []

    /// 自動 pull 方針。`eager` で全件 pull、`thumbsOnly` で原本は手動 DL。
    var autoPullPolicy: ICloudAutoPullPolicy = .eager

    private var query: NSMetadataQuery?
    private var observers: [Any] = []
    private let containerIdentifier: String

    // ネットワーク断を検知して .offline を表示するための監視。
    // NSMetadataQuery はオフラインでも pending を報告し続けるため、
    // 転送が進まない理由をユーザーに区別して見せる。
    private var pathMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    // processQueryResults の集計結果。ネットワーク状態と合成して syncStatus を導出する
    private var lastPendingCount = 0
    private var lastErrorMessage: String?

    init(containerIdentifier: String = "iCloud.com.spade3.DraftCanvas") {
        self.containerIdentifier = containerIdentifier
    }

    func start(containerURL: URL) {
        stop()

        let pm = NWPathMonitor()
        pm.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, available != self.isNetworkAvailable else { return }
                self.isNetworkAvailable = available
                if available {
                    // 復帰時は最新のクエリ結果で再評価する
                    self.refresh()
                } else {
                    self.updateSyncStatus()
                }
            }
        }
        pm.start(queue: DispatchQueue(label: "local.draftcanvas.network-path"))
        pathMonitor = pm

        let query = NSMetadataQuery()
        // 自アプリの Ubiquity コンテナ配下に限定。Ubiquitous*Scope 定数は iCloud Drive 全体を対象にしてしまい、
        // 他アプリのアップロード待ちファイルでも pending 扱いになり同期が永遠に終わらない原因になる。
        query.searchScopes = [containerURL]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        self.query = query

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.processQueryResults() }
        })
        observers.append(nc.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.processQueryResults() }
        })

        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        for obs in observers { NotificationCenter.default.removeObserver(obs) }
        observers.removeAll()
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// クエリ更新通知が届かず状態が固着した場合に備え、現在のクエリ結果を手動で再評価する。
    /// アプリが前面復帰したタイミング等で呼ぶ。
    func refresh() {
        guard query != nil else { return }
        processQueryResults()
    }

    func requestDownload(for url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    func isDownloaded(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else {
            return true
        }
        return values.ubiquitousItemDownloadingStatus != .notDownloaded
    }

    private func processQueryResults() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var totalSize: Int64 = 0
        var pendingCount = 0
        var downloading = Set<UUID>()
        var errorCount = 0
        var firstErrorDescription: String?

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }

            if let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 {
                totalSize += size
            }

            // アイテム単位の転送エラー（容量超過・権限等）を集計する
            let downloadError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            let uploadError = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
            if let transferError = downloadError ?? uploadError {
                errorCount += 1
                if firstErrorDescription == nil {
                    firstErrorDescription = transferError.localizedDescription
                }
            }

            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloading = (item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool) ?? false
            let isUploading = (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) ?? false
            let isUploaded = (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? true

            let needsDownload = downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded
            if needsDownload || isDownloading || isUploading || !isUploaded {
                pendingCount += 1
            }

            if needsDownload, !isDownloading,
               let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                if shouldAutoPull(url: url) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }

            if let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String {
                let stem = (name as NSString).deletingPathExtension
                if let uuid = UUID(uuidString: stem), needsDownload || isDownloading {
                    downloading.insert(uuid)
                }
            }
        }

        totalDataSize = totalSize
        totalItemCount = query.resultCount
        downloadingItemIDs = downloading

        lastPendingCount = pendingCount
        if let firstErrorDescription {
            lastErrorMessage = errorCount > 1
                ? String(localized: "同期エラー (\(errorCount)件): \(firstErrorDescription)")
                : String(localized: "同期エラー: \(firstErrorDescription)")
        } else {
            lastErrorMessage = nil
        }
        updateSyncStatus()
    }

    // 優先度: オフライン > 転送エラー > 同期中 > 同期完了
    private func updateSyncStatus() {
        if !isNetworkAvailable {
            syncStatus = .offline
        } else if let message = lastErrorMessage {
            syncStatus = .error(message)
        } else if lastPendingCount > 0 {
            syncStatus = .syncing(pending: lastPendingCount)
        } else {
            syncStatus = .synced
        }
    }

    private func shouldAutoPull(url: URL) -> Bool {
        switch autoPullPolicy {
        case .eager:
            return true
        case .thumbsOnly:
            let path = url.path
            if path.contains("/.thumbs/") || path.contains("/.thumbs.nosync/") {
                return true
            }
            return ICloudAutoPullPolicy.isMetadataExtension(url.pathExtension)
        }
    }

    nonisolated static func iCloudContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.spade3.DraftCanvas")?
            .appendingPathComponent("Documents")
    }

    nonisolated static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
