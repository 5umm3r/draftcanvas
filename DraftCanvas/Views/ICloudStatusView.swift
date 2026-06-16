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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                    if case .syncing(let pending) = syncMonitor.syncStatus {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: syncBarWidth(total: geo.size.width, pending: pending))
                            .animation(.easeInOut(duration: 0.3), value: pending)
                    } else if syncMonitor.syncStatus == .synced {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.5))
                    }
                }
            }
            .frame(height: 3)
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
        case .syncing(let pending): return "\(pending) ファイル同期中..."
        case .error(let msg): return LocalizedStringKey(msg)
        case .offline: return "オフライン"
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: syncMonitor.totalDataSize, countStyle: .file)
    }

    private func syncBarWidth(total: CGFloat, pending: Int) -> CGFloat {
        guard pending > 0 else { return total }
        let progress = max(0.1, 1.0 - Double(pending) / 100.0)
        return total * CGFloat(progress)
    }
}
