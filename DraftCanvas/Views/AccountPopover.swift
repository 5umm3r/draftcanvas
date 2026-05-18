import SwiftUI

struct AccountPopover: View {
    let status: CodexAccountUsageStatus
    let isLoading: Bool
    let hasFailed: Bool
    let codexVersion: String
    let onRetry: () -> Void
    let onRelaunchAndRetry: () -> Void

    private var planDisplay: String {
        if status.planLabel == "-" || status.planLabel.isEmpty {
            return status.accountKind.japaneseLabel
        }
        return "\(status.accountKind.japaneseLabel) \(status.planLabel.capitalized)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("読み込み中...")
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if status.accountKind == .unauthenticated {
                HStack(spacing: 10) {
                    Image(systemName: status.accountKind.systemImageName)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未ログイン")
                            .font(.headline)
                            .lineLimit(1)
                        Text("Codex CLI で `codex login` を実行")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                if hasFailed {
                    Button("再試行", action: onRelaunchAndRetry)
                        .padding(.top, 8)
                }
                Divider()
                    .padding(.vertical, 10)
                HStack {
                    Text("Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(codexVersion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else if hasFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("取得に失敗しました")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button("再試行", action: onRetry)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: status.accountKind.systemImageName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.accountLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Text(planDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if status.isChatGPTFreePlan {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(String(localized: "画像生成には ChatGPT Plus 以上のプランが必要です"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Button(action: onRelaunchAndRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                    .help(String(localized: "アカウント情報を再取得"))
                }
                Divider()
                    .padding(.vertical, 10)
                HStack {
                    Text("Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(codexVersion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
