import Foundation
import Combine
import Network

enum ICloudSyncStatus: Equatable {
    case disabled
    case synced
    /// 同期セッション単位の進捗。`total` は「このセッションで一度でも pending だった件数」で
    /// 単調増加、`completed` は完了到達件数で単調増加。瞬間の残数を出すと daemon の
    /// フラグ往復や新規ファイル流入で数字が増減して見えるため、進捗形式で表示する。
    case syncing(completed: Int, total: Int)
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
    /// 既定は `thumbsOnly`: 原本まで全件 pull すると初回同期の転送量が桁で増え、
    /// iCloud daemon の輻輳で同期完了までが極端に遅くなる。
    var autoPullPolicy: ICloudAutoPullPolicy = .thumbsOnly

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

    // 同期セッションの進捗。pendingCount は毎回ゼロから再集計する瞬間値のため、
    // 新規ファイル流入と転送完了が同時に起きると 5→6→4→6 と逆行して見える。
    // 「一度でも pending だった集合」を分母、そこから抜けた件数を分子にして単調化する。
    private var syncSessionTotalPaths: Set<String> = []
    private var syncSessionPendingPaths: Set<String> = []
    // URL を取れず同一性を追えないアイテム。分母・分子の双方に同数を足して進捗を歪めない。
    private var untrackedPendingCount = 0

    // pending が 0 になっても daemon が直後に再アップロードを立てることがあり、
    // 即 .synced にすると「完了→同期中」を往復する。連続で 0 を観測してから確定する。
    private var consecutiveZeroPendingCount = 0
    private let requiredZeroPendingStreak = 2

    // 自動 DL 要求の再送抑制。ポーリングのたび未 DL 全件に
    // startDownloadingUbiquitousItem を投げると daemon に無駄な要求が溜まる。
    // 一度要求したパスは、DL が始まらないまま一定時間経過した場合のみ再要求する。
    private var downloadRequestedAt: [String: ContinuousClock.Instant] = [:]
    private let downloadRetryInterval: Duration = .seconds(30)

    // アップロード完了を観測した時点のスナップショット。daemon はメタデータ更新の
    // たび isUploaded を false に戻すことがあり、同一ファイルが pending に復帰して
    // 件数が逆行する。内容変更日時が変わっていなければフラグ往復とみなす。
    private var lastUploadedObservations: [String: (changeDate: Date, observedAt: ContinuousClock.Instant)] = [:]
    private let uploadFlapGrace: Duration = .seconds(30)

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
        resetSyncSession()
        downloadRequestedAt.removeAll()
        lastUploadedObservations.removeAll()
    }

    private func resetSyncSession() {
        syncSessionTotalPaths.removeAll()
        syncSessionPendingPaths.removeAll()
        untrackedPendingCount = 0
        consecutiveZeroPendingCount = 0
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
        var seenPaths = Set<String>()
        var pendingPaths = Set<String>()
        var untracked = 0
        let now = ContinuousClock().now

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

            let identity = (item.value(forAttribute: NSMetadataItemPathKey) as? String) ?? url?.path
            if let identity { seenPaths.insert(identity) }

            // アップロード完了直後の isUploaded 往復を吸収する。内容変更日時が
            // 前回 uploaded 観測時から変わっていなければ実体は変わっていない
            let contentChangeDate = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let uploadedSnapshot = identity.flatMap { lastUploadedObservations[$0] }
            let effectiveIsUploaded = isUploaded || Self.isSpuriousUploadFlap(
                isUploading: isUploading,
                isUploaded: isUploaded,
                contentChangeDate: contentChangeDate,
                lastUploadedChangeDate: uploadedSnapshot?.changeDate,
                lastUploadedObservedAt: uploadedSnapshot?.observedAt,
                now: now,
                grace: uploadFlapGrace
            )
            if isUploaded, !isUploading, let identity, let contentChangeDate {
                lastUploadedObservations[identity] = (contentChangeDate, now)
            }

            if Self.isPendingTransfer(
                needsDownload: needsDownload,
                isDownloading: isDownloading,
                isUploading: isUploading,
                isUploaded: effectiveIsUploaded,
                autoPullWanted: autoPullWanted
            ) {
                pendingCount += 1
                if let identity {
                    pendingPaths.insert(identity)
                } else {
                    untracked += 1
                }
            }

            // 自動 DL 要求は再送を抑制する。要求済みパスは DL が始まらないまま
            // downloadRetryInterval を過ぎた場合のみ再投入する
            if let url {
                if Self.shouldRequestDownload(
                    needsDownload: needsDownload,
                    isDownloading: isDownloading,
                    autoPullWanted: autoPullWanted,
                    lastRequestedAt: identity.flatMap { downloadRequestedAt[$0] },
                    now: now,
                    retryInterval: downloadRetryInterval
                ) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    if let identity { downloadRequestedAt[identity] = now }
                } else if !needsDownload || isDownloading, let identity {
                    // DL 開始済み or 完了 → 記録を捨てて次回の未 DL 検出に備える
                    downloadRequestedAt.removeValue(forKey: identity)
                }
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
        // 削除・コンテナ外へ移動したアイテムは分母から落とす（永久に未完了扱いになるのを防ぐ）
        syncSessionTotalPaths.formIntersection(seenPaths)
        syncSessionTotalPaths.formUnion(pendingPaths)
        syncSessionPendingPaths = pendingPaths
        untrackedPendingCount = untracked
        // クエリから消えたパスの記録を捨てる（長時間稼働で辞書が肥大するのを防ぐ）
        downloadRequestedAt = downloadRequestedAt.filter { seenPaths.contains($0.key) }
        lastUploadedObservations = lastUploadedObservations.filter { seenPaths.contains($0.key) }

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
            consecutiveZeroPendingCount = 0
            syncStatus = Self.progressStatus(
                totalTracked: syncSessionTotalPaths.count,
                pendingTracked: syncSessionPendingPaths.count,
                untrackedPending: untrackedPendingCount
            )
        } else if syncSessionTotalPaths.isEmpty {
            // このセッションで一度も pending がない（起動直後の同期済み状態）。待つ理由がない
            resetSyncSession()
            syncStatus = .synced
        } else {
            // 完了確定前に猶予を挟む。ポーラーは syncing 中のみ回るため、
            // 完了扱いの syncing を出しておくことで次回評価が 3 秒後に届く
            consecutiveZeroPendingCount += 1
            if consecutiveZeroPendingCount >= requiredZeroPendingStreak {
                resetSyncSession()
                syncStatus = .synced
            } else {
                let total = syncSessionTotalPaths.count
                syncStatus = .syncing(completed: total, total: total)
            }
        }
        adjustSyncingPoller()
    }

    /// 分子・分母とも単調増加になるよう合成する。追跡不能アイテムは双方に同数足して進捗率を歪めない。
    nonisolated static func progressStatus(
        totalTracked: Int,
        pendingTracked: Int,
        untrackedPending: Int
    ) -> ICloudSyncStatus {
        let total = totalTracked + untrackedPending
        let completed = max(0, totalTracked - pendingTracked)
        return .syncing(completed: completed, total: max(total, completed))
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

    /// アップロード完了後、daemon がメタデータ更新のたび isUploaded を false に戻すことがある。
    /// 実体の変更を伴わないこの往復を pending に数えると同一ファイルが何度も未完了に復帰し、
    /// 件数が逆行して見える。内容変更日時が前回 uploaded 観測時から変わっていなければ往復とみなす。
    ///
    /// 実際に転送中 (isUploading) のものは対象外。猶予を過ぎたら通常どおり pending に戻し、
    /// 再アップロードが必要な本物のケースを取りこぼさない。
    nonisolated static func isSpuriousUploadFlap(
        isUploading: Bool,
        isUploaded: Bool,
        contentChangeDate: Date?,
        lastUploadedChangeDate: Date?,
        lastUploadedObservedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        grace: Duration
    ) -> Bool {
        guard !isUploaded, !isUploading else { return false }
        guard let contentChangeDate,
              let lastUploadedChangeDate,
              let lastUploadedObservedAt,
              contentChangeDate == lastUploadedChangeDate
        else { return false }
        return now - lastUploadedObservedAt < grace
    }

    /// 自動 DL 要求を投げるべきか。未要求なら即投入、要求済みなら DL が始まらないまま
    /// retryInterval を過ぎた場合のみ再投入する。ポーリングのたび全件へ再要求すると
    /// iCloud daemon に無駄な要求が積み上がり転送全体が遅くなる。
    nonisolated static func shouldRequestDownload(
        needsDownload: Bool,
        isDownloading: Bool,
        autoPullWanted: Bool,
        lastRequestedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        retryInterval: Duration
    ) -> Bool {
        guard needsDownload, !isDownloading, autoPullWanted else { return false }
        guard let lastRequestedAt else { return true }
        return now - lastRequestedAt >= retryInterval
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

/// iCloud サインイン状態の監視。
///
/// `ICloudSyncMonitor.isICloudAvailable` を View の body から直読みすると、
/// `FileManager.ubiquityIdentityToken` の変化を SwiftUI が購読できず、
/// サインイン / サインアウトしても表示が更新されない。
/// アプリと同じ寿命の共有インスタンスとして通知を監視する。
@MainActor
final class ICloudAvailability: ObservableObject {
    static let shared = ICloudAvailability()

    @Published private(set) var isAvailable: Bool

    private init() {
        isAvailable = ICloudSyncMonitor.isICloudAvailable
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAvailable = ICloudSyncMonitor.isICloudAvailable
            }
        }
    }
}
