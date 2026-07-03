import XCTest
@testable import DraftCanvas

@MainActor
final class ICloudSyncMonitorTests: XCTestCase {
    func test_totalItemCount_initiallyZero() {
        let monitor = ICloudSyncMonitor(containerIdentifier: "iCloud.test.fake")
        XCTAssertEqual(monitor.totalItemCount, 0)
    }

    func test_autoPullPolicy_defaultsToEager() {
        let monitor = ICloudSyncMonitor(containerIdentifier: "iCloud.test.fake")
        XCTAssertEqual(monitor.autoPullPolicy, .eager)
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
