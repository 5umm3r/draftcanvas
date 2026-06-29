import Foundation

/// 原本ファイル単位のアクセス時刻記録と LRU 退避。
///
/// UserDefaults 上の plist (`iCloudAccessTimestamps`) に `[path: epochSeconds]` を保存。
/// 退避時は `evictUbiquitousItem` でローカル副本を解放。
actor ICloudCacheEviction {
    static let timestampsKey = "iCloudAccessTimestamps"
    static let limitBytesKey = "iCloudCacheLimitBytes"
    static let defaultLimitBytes: Int64 = 2 * 1024 * 1024 * 1024  // 2 GB

    private let defaults: UserDefaults
    private var timestamps: [String: TimeInterval]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.timestamps = (defaults.dictionary(forKey: Self.timestampsKey) as? [String: TimeInterval]) ?? [:]
    }

    func recordAccess(url: URL) {
        let now = Date().timeIntervalSince1970
        timestamps[url.path] = now
        defaults.set(timestamps, forKey: Self.timestampsKey)
    }

    func lastAccess(url: URL) -> Date? {
        guard let ts = timestamps[url.path] else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
