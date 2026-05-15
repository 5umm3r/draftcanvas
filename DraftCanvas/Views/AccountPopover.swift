import SwiftUI

struct AccountPopover: View {
    @EnvironmentObject private var l10n: LocalizationManager

    let status: CodexAccountUsageStatus
    let isLoading: Bool
    let hasFailed: Bool
    let isLoggingOut: Bool
    let codexVersion: String
    let onRetry: () -> Void
    let onLogout: () -> Void

    private var canLogout: Bool {
        status.accountKind == .chatgpt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView(L("読み込み中..."))
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if hasFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("取得に失敗しました"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button(L("再試行"), action: onRetry)
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
                        if status.planLabel != "-" {
                            Text(status.planLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                }

                Text("Codex \(codexVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                if canLogout {
                    Button(action: onLogout) {
                        HStack(spacing: 6) {
                            if isLoggingOut {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text(L("ログアウト"))
                        }
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoggingOut)
                    .padding(.top, 10)
                }

                Divider().padding(.vertical, 12)

                HStack {
                    Text(L("言語 / Language"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { l10n.current },
                        set: { l10n.current = $0 }
                    )) {
                        ForEach(LocalizationManager.AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
