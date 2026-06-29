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
}
