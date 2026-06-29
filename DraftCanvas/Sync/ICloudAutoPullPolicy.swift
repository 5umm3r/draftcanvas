import Foundation

/// iCloud クエリ結果に対する自動ダウンロード方針。
///
/// - eager: 全未 DL ファイルを即座に pull (1.2 系までの挙動)。
/// - thumbsOnly: `.thumbs` / `.thumbs.nosync` 配下とプロジェクト JSON のみ自動 pull。
///   原本 (`.png` / `.jpg` / `.webp` / `.svg` / `.heic`) はオンデマンド DL に委ねる。
enum ICloudAutoPullPolicy: String, Codable, Sendable {
    case eager
    case thumbsOnly

    static let userDefaultsKey = "iCloudAutoPullPolicy"

    /// UserDefaults から読み出す。未設定 (既定) は eager。
    static func load(from defaults: UserDefaults = .standard) -> ICloudAutoPullPolicy {
        guard let raw = defaults.string(forKey: userDefaultsKey),
              let policy = ICloudAutoPullPolicy(rawValue: raw)
        else { return .eager }
        return policy
    }

    /// 拡張子からサムネ/メタデータ系かどうかを判定。
    static func isMetadataExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "json", "plist": return true
        default: return false
        }
    }
}
