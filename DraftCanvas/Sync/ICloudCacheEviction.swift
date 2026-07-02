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
    private var persistTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.timestamps = (defaults.dictionary(forKey: Self.timestampsKey) as? [String: TimeInterval]) ?? [:]
    }

    func recordAccess(url: URL) {
        let now = Date().timeIntervalSince1970
        timestamps[url.path] = now
        schedulePersist()
    }

    // 画像表示のたびに辞書全体を UserDefaults へシリアライズすると、
    // エントリ数に比例して I/O が増幅するためデバウンスして書き込む。
    // 終了時に直近数秒の記録が失われても LRU が僅かにずれるだけで実害はない。
    private func schedulePersist() {
        guard persistTask == nil else { return }
        persistTask = Task {
            try? await Task.sleep(for: .seconds(2))
            persistTask = nil
            defaults.set(timestamps, forKey: Self.timestampsKey)
        }
    }

    func lastAccess(url: URL) -> Date? {
        guard let ts = timestamps[url.path] else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var limitBytes: Int64 {
        let raw = defaults.object(forKey: Self.limitBytesKey) as? Int64
        return raw ?? Self.defaultLimitBytes
    }

    func setLimitBytes(_ value: Int64) {
        defaults.set(value, forKey: Self.limitBytesKey)
    }

    func forgetAccess(url: URL) {
        timestamps.removeValue(forKey: url.path)
        schedulePersist()
    }
}

struct ICloudCacheEntry: Sendable {
    let url: URL
    let size: Int64
    let lastAccess: Date
}

extension ICloudCacheEviction {
    /// 上限を超えるぶんを LRU で選び、evict 対象 URL を返す (実 evict は呼出側)。
    func enforceLimit(entries: [ICloudCacheEntry]) -> [URL] {
        let limit = limitBytes
        guard limit > 0 else { return [] }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return [] }
        var overflow = total - limit
        var evicted: [URL] = []
        let sorted = entries.sorted { $0.lastAccess < $1.lastAccess }
        for entry in sorted where overflow > 0 {
            evicted.append(entry.url)
            overflow -= entry.size
        }
        return evicted
    }

    /// FileManager.evictUbiquitousItem を呼びローカル副本を解放。
    /// 戻り値: true=成功, false=エラー or 対象が iCloud 配下でない。
    @discardableResult
    nonisolated static func evict(url: URL) -> Bool {
        do {
            try FileManager.default.evictUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
