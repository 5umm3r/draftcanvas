import SwiftUI

struct ICloudStatusView: View {
    @ObservedObject var syncMonitor: ICloudSyncMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text("iCloud")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedSize)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if case .syncing(let completed, let total) = syncMonitor.syncStatus {
                // 進捗は単調増加のため確定値バーで出せる。total 0 は不定表示に落とす
                if total > 0 {
                    ProgressView(value: Double(completed), total: Double(total))
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
            }
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusIcon: String {
        switch syncMonitor.syncStatus {
        case .disabled: return "icloud.slash"
        case .synced: return "checkmark.icloud"
        case .syncing: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.icloud"
        case .offline: return "icloud.slash"
        }
    }

    private var statusColor: Color {
        switch syncMonitor.syncStatus {
        case .disabled, .offline: return .secondary
        case .synced: return .green
        case .syncing: return .accentColor
        case .error: return .red
        }
    }

    private var statusText: LocalizedStringKey {
        switch syncMonitor.syncStatus {
        case .disabled: return "iCloud同期無効"
        case .synced: return "同期完了"
        case .syncing(let completed, let total): return "\(completed) / \(total) ファイル同期中..."
        case .error(let msg): return LocalizedStringKey(msg)
        case .offline: return "オフライン"
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: syncMonitor.totalDataSize, countStyle: .file)
    }

}

/// syncMonitor 未生成時（同期オフ / 未サインイン / 有効化後の再起動待ち）のステータス表示。
/// 同期トグルは再起動反映方式のため、セッション中に monitor が後から生えるのは
/// 起動直後のコンテナ解決時のみ。
struct ICloudInactiveStatusView: View {
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("iCloud")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: LocalizedStringKey {
        if !iCloudSyncEnabled {
            return "同期オフ"
        }
        if !ICloudSyncMonitor.isICloudAvailable {
            return "未サインイン"
        }
        return "再起動後に同期を開始"
    }
}
