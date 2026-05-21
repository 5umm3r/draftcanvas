import SwiftUI

struct LicenseSheet: View {
    @ObservedObject private var gate = EntitlementGate.shared
    @State private var key = ""
    @State private var activated = false
    @State private var confirmDeactivate = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if activated {
                activatedView
            } else if gate.status == .licensed {
                managementView
            } else {
                activationView
            }
        }
        .padding(40)
        .frame(width: 420)
        .onDisappear { gate.licenseError = nil }
    }

    private var activatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text(String(localized: "有効化完了"))
                .font(.title2.bold())
            Text(String(localized: "Draft Canvas のすべての機能が使えるようになりました。"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "閉じる")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var managementView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text(String(localized: "ライセンス認証済み"))
                    .font(.title3.bold())
                if let k = LicenseStore.shared.licenseKey {
                    Text(maskedKey(k))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            VStack(spacing: 12) {
                Button {
                    confirmDeactivate = true
                } label: {
                    Text(String(localized: "このMacのライセンスを解除"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
                .frame(maxWidth: 260)

                Button(String(localized: "閉じる")) { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            String(localized: "ライセンスを解除しますか？"),
            isPresented: $confirmDeactivate,
            titleVisibility: .visible
        ) {
            Button(String(localized: "解除する"), role: .destructive) {
                Task {
                    await gate.deactivateLicense()
                    dismiss()
                }
            }
            Button(String(localized: "キャンセル"), role: .cancel) {}
        } message: {
            Text(String(localized: "このMacのアクティベーションが解除されます。別のMacで使用する際に再入力が必要です。"))
        }
    }

    private var activationView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(String(localized: "ライセンスを有効化"))
                    .font(.title2.bold())
                Text(String(localized: "購入後に届いたライセンスキーを入力してください。"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                NSWorkspace.shared.open(PurchaseConfig.purchaseURL)
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "ライセンスをお持ちでない方は"))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "購入する"))
                        .foregroundStyle(Color.accentColor)
                }
                .font(.caption)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 340)
                    .onSubmit { Task { await activate() } }

                if let error = gate.licenseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(spacing: 12) {
                Button {
                    Task { await activate() }
                } label: {
                    Group {
                        if gate.isActivating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "有効化する"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || gate.isActivating)
                .frame(maxWidth: 260)

                Button(String(localized: "キャンセル")) { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activate() async {
        await gate.activateLicense(key: key.trimmingCharacters(in: .whitespaces))
        if gate.status == .licensed { activated = true }
    }

    private func maskedKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count >= 2 else { return String(repeating: "•", count: min(key.count, 20)) }
        let visible = String(parts[0])
        let masked = parts.dropFirst().map { String(repeating: "•", count: $0.count) }
        return ([visible] + masked).joined(separator: "-")
    }
}
