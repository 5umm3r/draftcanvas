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

extension Notification.Name {
    /// ローカル書込直後に post。iCloud daemon の反映を待つため
    /// ICloudSyncMonitor が定期 refresh を数秒間走らせて query キャッシュを吸い上げる。
    static let draftCanvasICloudLocalWrite = Notification.Name("DraftCanvas.iCloudLocalWrite")
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

    // syncing 継続中の定期 refresh。NSMetadataQueryDidUpdate は
    // 属性のみ変化 (isUploaded false→true) では発火しないケースがあり、
    // アップロード完了しても表示が「同期中」で固着する。定期 refresh で強制再評価する。
    private var syncingPoller: Task<Void, Never>?
    private let syncingPollInterval: Duration = .seconds(3)

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

        let query = Self.makeQuery(containerURL: containerURL)
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
        // ローカル書込直後は NSMetadataQuery が新規ファイルを認識するまで数秒遅延がある。
        // 書込 notification を受けたら syncing に一時遷移させ、以降のポーリングで反映を吸う。
        observers.append(nc.addObserver(
            forName: .draftCanvasICloudLocalWrite,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
        syncingPoller?.cancel()
        syncingPoller = nil
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
            let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
            // URL が取れないアイテムは安全側（pending 扱い）に倒す
            let autoPullWanted = url.map { shouldAutoPull(url: $0) } ?? true

            if Self.isPendingTransfer(
                needsDownload: needsDownload,
                isDownloading: isDownloading,
                isUploading: isUploading,
                isUploaded: isUploaded,
                autoPullWanted: autoPullWanted
            ) {
                pendingCount += 1
            }

            if needsDownload, !isDownloading, autoPullWanted, let url {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }

            if let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String {
                let stem = (name as NSString).deletingPathExtension
                if let uuid = UUID(uuidString: stem),
                   isDownloading || (needsDownload && autoPullWanted) {
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
        adjustSyncingPoller()
    }

    /// syncing 継続中のみ定期 refresh を走らせる。synced/offline/error/disabled では止める。
    private func adjustSyncingPoller() {
        if case .syncing = syncStatus {
            if syncingPoller == nil {
                syncingPoller = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let interval = self.syncingPollInterval
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        if Task.isCancelled { return }
                        self.processQueryResults()
                    }
                }
            }
        } else {
            syncingPoller?.cancel()
            syncingPoller = nil
        }
    }

    private func shouldAutoPull(url: URL) -> Bool {
        Self.shouldAutoPull(url: url, policy: autoPullPolicy)
    }

    nonisolated static func shouldAutoPull(url: URL, policy: ICloudAutoPullPolicy) -> Bool {
        switch policy {
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

    /// 同期未完了 (pending) として数えるかを判定する。
    /// 未 DL でも autoPullWanted が false のアイテムは pending に含めない。
    /// 省容量モード (thumbsOnly) では原本を意図的に未 DL のまま残すため、
    /// これを pending に数えると受信側端末の同期が永遠に「同期中」のまま終わらない。
    nonisolated static func isPendingTransfer(
        needsDownload: Bool,
        isDownloading: Bool,
        isUploading: Bool,
        isUploaded: Bool,
        autoPullWanted: Bool
    ) -> Bool {
        if isDownloading || isUploading || !isUploaded { return true }
        return needsDownload && autoPullWanted
    }

    /// プレーン URL を searchScopes に渡すと Spotlight インデックス依存になり、
    /// ~/Library/Mobile Documents は索引対象外のため常に 0 件（サイズ 0 KB・
    /// 「同期完了」誤表示・自動 DL 不発の原因）。Ubiquitous スコープで iCloud
    /// デーモンのインデックスを参照し、iCloud Drive 全体の巻き込み（他アプリの
    /// pending 待ち）はコンテナパス前方一致の predicate で防ぐ。
    nonisolated static func makeQuery(containerURL: URL) -> NSMetadataQuery {
        let query = NSMetadataQuery()
        query.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            NSMetadataQueryUbiquitousDataScope,
        ]
        query.predicate = NSPredicate(
            format: "%K BEGINSWITH %@", NSMetadataItemPathKey, containerURL.path + "/"
        )
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        return query
    }

    nonisolated static func iCloudContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.spade3.DraftCanvas")?
            .appendingPathComponent("Documents")
    }

    nonisolated static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
