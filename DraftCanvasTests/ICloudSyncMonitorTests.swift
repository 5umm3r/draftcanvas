import XCTest
@testable import DraftCanvas

@MainActor
final class ICloudSyncMonitorTests: XCTestCase {
    func test_totalItemCount_initiallyZero() {
        let monitor = ICloudSyncMonitor(containerIdentifier: "iCloud.test.fake")
        XCTAssertEqual(monitor.totalItemCount, 0)
    }

    // 原本まで全件 pull すると初回同期の転送量が桁で増えるため、既定は省容量側
    func test_autoPullPolicy_defaultsToThumbsOnly() {
        let monitor = ICloudSyncMonitor(containerIdentifier: "iCloud.test.fake")
        XCTAssertEqual(monitor.autoPullPolicy, .thumbsOnly)
    }

    func test_autoPullPolicyLoad_unsetDefaultsToThumbsOnly() {
        let defaults = UserDefaults(suiteName: "test.autoPull.unset")!
        defaults.removeObject(forKey: ICloudAutoPullPolicy.userDefaultsKey)
        XCTAssertEqual(ICloudAutoPullPolicy.load(from: defaults), .thumbsOnly)
    }

    func test_autoPullPolicyLoad_explicitEagerIsRespected() {
        let defaults = UserDefaults(suiteName: "test.autoPull.eager")!
        defaults.set(ICloudAutoPullPolicy.eager.rawValue, forKey: ICloudAutoPullPolicy.userDefaultsKey)
        XCTAssertEqual(ICloudAutoPullPolicy.load(from: defaults), .eager)
        defaults.removeObject(forKey: ICloudAutoPullPolicy.userDefaultsKey)
    }

    func test_autoPullPolicy_canBeSet() {
        let monitor = ICloudSyncMonitor(containerIdentifier: "iCloud.test.fake")
        monitor.autoPullPolicy = .thumbsOnly
        XCTAssertEqual(monitor.autoPullPolicy, .thumbsOnly)
    }

    // プレーン URL スコープは Spotlight 依存で ~/Library/Mobile Documents を
    // 索引しないため常に 0 件になる。Ubiquitous スコープであることを保証する。
    func test_makeQuery_usesUbiquitousScopes_notPlainURL() {
        let query = ICloudSyncMonitor.makeQuery(
            containerURL: URL(fileURLWithPath: "/tmp/Container/Documents")
        )
        let scopes = query.searchScopes.compactMap { $0 as? String }
        XCTAssertTrue(scopes.contains(NSMetadataQueryUbiquitousDocumentsScope))
        XCTAssertTrue(scopes.contains(NSMetadataQueryUbiquitousDataScope))
        XCTAssertFalse(query.searchScopes.contains { $0 is URL })
    }

    // 省容量モードで意図的に未 DL のまま残す原本を pending に数えると、
    // 受信側端末の同期ステータスが永遠に「同期中」のまま完了しない
    func test_isPendingTransfer_undownloadedOutsideAutoPull_isNotPending() {
        XCTAssertFalse(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: true, isDownloading: false,
            isUploading: false, isUploaded: true, autoPullWanted: false
        ))
    }

    func test_isPendingTransfer_undownloadedWithAutoPull_isPending() {
        XCTAssertTrue(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: true, isDownloading: false,
            isUploading: false, isUploaded: true, autoPullWanted: true
        ))
    }

    // 実際に転送中のアイテムはポリシーに関係なく pending
    func test_isPendingTransfer_activeTransfer_isPendingRegardlessOfAutoPull() {
        XCTAssertTrue(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: false, isDownloading: true,
            isUploading: false, isUploaded: true, autoPullWanted: false
        ))
        XCTAssertTrue(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: false, isDownloading: false,
            isUploading: true, isUploaded: true, autoPullWanted: false
        ))
        XCTAssertTrue(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: false, isDownloading: false,
            isUploading: false, isUploaded: false, autoPullWanted: false
        ))
    }

    func test_isPendingTransfer_downloadedIdleItem_isNotPending() {
        XCTAssertFalse(ICloudSyncMonitor.isPendingTransfer(
            needsDownload: false, isDownloading: false,
            isUploading: false, isUploaded: true, autoPullWanted: true
        ))
    }

    func test_shouldAutoPull_eager_pullsEverything() {
        XCTAssertTrue(ICloudSyncMonitor.shouldAutoPull(
            url: URL(fileURLWithPath: "/c/Documents/items/a.png"), policy: .eager
        ))
    }

    func test_shouldAutoPull_thumbsOnly_pullsThumbsAndMetadataOnly() {
        XCTAssertTrue(ICloudSyncMonitor.shouldAutoPull(
            url: URL(fileURLWithPath: "/c/Documents/.thumbs/a.png"), policy: .thumbsOnly
        ))
        XCTAssertTrue(ICloudSyncMonitor.shouldAutoPull(
            url: URL(fileURLWithPath: "/c/Documents/.thumbs.nosync/a.png"), policy: .thumbsOnly
        ))
        XCTAssertTrue(ICloudSyncMonitor.shouldAutoPull(
            url: URL(fileURLWithPath: "/c/Documents/project.json"), policy: .thumbsOnly
        ))
        XCTAssertFalse(ICloudSyncMonitor.shouldAutoPull(
            url: URL(fileURLWithPath: "/c/Documents/items/a.png"), policy: .thumbsOnly
        ))
    }

    // 分子は「一度でも pending だった集合から抜けた件数」。分母は単調増加のため、
    // 新規ファイル流入があっても表示が逆行しない
    func test_progressStatus_completedIsTotalMinusPending() {
        XCTAssertEqual(
            ICloudSyncMonitor.progressStatus(totalTracked: 8, pendingTracked: 3, untrackedPending: 0),
            .syncing(completed: 5, total: 8)
        )
    }

    func test_progressStatus_newArrivalsGrowDenominatorNotShrinkNumerator() {
        // 5 件中 2 件完了 → 新規 4 件流入で pending 7 / total 9
        let before = ICloudSyncMonitor.progressStatus(
            totalTracked: 5, pendingTracked: 3, untrackedPending: 0
        )
        let after = ICloudSyncMonitor.progressStatus(
            totalTracked: 9, pendingTracked: 7, untrackedPending: 0
        )
        guard case .syncing(let beforeDone, let beforeTotal) = before,
              case .syncing(let afterDone, let afterTotal) = after else {
            return XCTFail("syncing でない")
        }
        XCTAssertGreaterThanOrEqual(afterDone, beforeDone)
        XCTAssertGreaterThanOrEqual(afterTotal, beforeTotal)
    }

    // URL を取れないアイテムは分母・分子の双方に効かせず、進捗率を歪めない
    func test_progressStatus_untrackedItemsCountTowardTotalOnly() {
        XCTAssertEqual(
            ICloudSyncMonitor.progressStatus(totalTracked: 4, pendingTracked: 1, untrackedPending: 2),
            .syncing(completed: 3, total: 6)
        )
    }

    func test_progressStatus_neverReportsCompletedAboveTotal() {
        guard case .syncing(let completed, let total) = ICloudSyncMonitor.progressStatus(
            totalTracked: 3, pendingTracked: 0, untrackedPending: 0
        ) else { return XCTFail("syncing でない") }
        XCTAssertLessThanOrEqual(completed, total)
    }

    func test_makeQuery_predicateMatchesOnlyContainerPath() throws {
        let query = ICloudSyncMonitor.makeQuery(
            containerURL: URL(fileURLWithPath: "/tmp/Container/Documents")
        )
        let predicate = try XCTUnwrap(query.predicate)
        XCTAssertTrue(predicate.evaluate(
            with: [NSMetadataItemPathKey: "/tmp/Container/Documents/items/a.png"]
        ))
        // 他アプリ・iCloud Drive 全体のファイルを pending 集計に巻き込まない
        XCTAssertFalse(predicate.evaluate(
            with: [NSMetadataItemPathKey: "/tmp/Other/App/file.png"]
        ))
        // 前方一致がパス区切り単位であること（兄弟ディレクトリ誤マッチ防止)
        XCTAssertFalse(predicate.evaluate(
            with: [NSMetadataItemPathKey: "/tmp/Container/DocumentsBackup/file.png"]
        ))
    }
}
