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

    func test_limitBytes_defaultsTo5GB() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        let limit = await eviction.limitBytes
        XCTAssertEqual(limit, 5 * 1024 * 1024 * 1024)
    }

    // 設定画面の @AppStorage は Int で書き込む。Int64 決め打ちで読むと取りこぼす
    func test_limitBytes_readsValueWrittenAsInt() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(5 * 1024 * 1024 * 1024 as Int, forKey: ICloudCacheEviction.limitBytesKey)
        let eviction = ICloudCacheEviction(defaults: defaults)
        let limit = await eviction.limitBytes
        XCTAssertEqual(limit, 5 * 1024 * 1024 * 1024)
    }

    func test_limitBytes_canBeSet() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        await eviction.setLimitBytes(5 * 1024 * 1024 * 1024)
        let limit = await eviction.limitBytes
        XCTAssertEqual(limit, 5 * 1024 * 1024 * 1024)
    }

    func test_enforceLimit_evictsOldestUntilUnderLimit() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        await eviction.setLimitBytes(100)
        let now = Date()
        let entries: [ICloudCacheEntry] = [
            .init(url: URL(fileURLWithPath: "/a"), size: 40, lastAccess: now.addingTimeInterval(-300)),
            .init(url: URL(fileURLWithPath: "/b"), size: 40, lastAccess: now.addingTimeInterval(-200)),
            .init(url: URL(fileURLWithPath: "/c"), size: 40, lastAccess: now.addingTimeInterval(-100)),
        ]
        let evicted = await eviction.enforceLimit(entries: entries)
        XCTAssertEqual(evicted.map(\.path), ["/a"])  // 合計 120 -> 目標 80 にするため最古を 1 件 evict
    }

    // 上限ちょうどまでしか削らないと、原本を 1 枚 DL しただけで再び超過し、
    // 起動のたび evict と再 DL を往復する
    func test_enforceLimit_evictsDownToTargetRatioNotJustUnderLimit() {
        let now = Date()
        let entries: [ICloudCacheEntry] = (0..<11).map {
            .init(
                url: URL(fileURLWithPath: "/\($0)"),
                size: 10,
                lastAccess: now.addingTimeInterval(TimeInterval(-1000 + $0))
            )
        }
        // 合計 110、上限 100。上限ちょうどなら 1 件で足りるが、目標 80 まで削る
        let evicted = ICloudCacheEviction.enforceLimit(entries: entries, limit: 100)
        XCTAssertEqual(evicted.map(\.path), ["/0", "/1", "/2"])
        let remaining = 110 - evicted.count * 10
        XCTAssertLessThanOrEqual(remaining, Int(Double(100) * ICloudCacheEviction.evictionTargetRatio))
    }

    // 上限以下なら閾値に達していないので何も削らない（目標水準まで削り込まない）
    func test_enforceLimit_underLimitEvictsNothing() {
        let entries: [ICloudCacheEntry] = [
            .init(url: URL(fileURLWithPath: "/a"), size: 90, lastAccess: Date()),
        ]
        XCTAssertTrue(ICloudCacheEviction.enforceLimit(entries: entries, limit: 100).isEmpty)
    }

    func test_enforceLimit_negativeLimitMeansUnlimited() {
        let entries: [ICloudCacheEntry] = [
            .init(url: URL(fileURLWithPath: "/a"), size: 999, lastAccess: Date()),
        ]
        XCTAssertTrue(ICloudCacheEviction.enforceLimit(entries: entries, limit: -1).isEmpty)
    }

    func test_enforceLimit_zeroLimitMeansUnlimited() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let eviction = ICloudCacheEviction(defaults: defaults)
        await eviction.setLimitBytes(0)
        let entries: [ICloudCacheEntry] = [
            .init(url: URL(fileURLWithPath: "/a"), size: 999_999_999, lastAccess: Date()),
        ]
        let evicted = await eviction.enforceLimit(entries: entries)
        XCTAssertTrue(evicted.isEmpty)
    }
}
