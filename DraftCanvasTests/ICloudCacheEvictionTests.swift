import XCTest
@testable import DraftCanvas

final class ICloudCacheEvictionTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
    }

    func test_recordAccess_persistsTimestamp() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/fake.png")
        await eviction.recordAccess(url: url)
        let stamp = await eviction.lastAccess(url: url)
        XCTAssertNotNil(stamp)
    }

    func test_lastAccess_nilForUnseenURL() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/never.png")
        let stamp = await eviction.lastAccess(url: url)
        XCTAssertNil(stamp)
    }

    func test_limitBytes_defaultsTo2GB() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        let limit = await eviction.limitBytes
        XCTAssertEqual(limit, 2 * 1024 * 1024 * 1024)
    }

    func test_limitBytes_canBeSet() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        await eviction.setLimitBytes(5 * 1024 * 1024 * 1024)
        let limit = await eviction.limitBytes
        XCTAssertEqual(limit, 5 * 1024 * 1024 * 1024)
    }
}
