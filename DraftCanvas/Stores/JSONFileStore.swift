import Foundation

// MARK: - JSONFileStore

/// JSON ファイルへの永続化を共通化するプロトコル。
/// 各 Store は `fileURL` を実装するだけで load / save を利用できる。
protocol JSONFileStore {
    associatedtype Payload: Codable
    var fileURL: URL { get }
}

// MARK: - Default implementations

extension JSONFileStore {

    /// ファイルが存在しない・デコード失敗の場合は `nil` を返す。
    /// 呼び出し側で `?? []` や `?? defaultValue` にする。
    func load() -> Payload? {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL)
        else { return nil }
        return try? JSONDecoder.projectDecoder.decode(Payload.self, from: data)
    }

    /// ファイル書き込み失敗は無視する（ProjectStore.save と同一パターン）。
    func save(_ payload: Payload) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder.projectEncoder.encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
