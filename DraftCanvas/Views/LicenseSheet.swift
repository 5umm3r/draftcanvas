import SwiftUI

struct LicenseSheet: View {
    @StateObject private var gate = EntitlementGate.shared
    @State private var key = ""
    @State private var activated = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            if activated {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text(L("有効化完了"))
                        .font(.title2.bold())
                    Text(L("Draft Canvas のすべての機能が使えるようになりました。"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(L("閉じる")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                VStack(spacing: 8) {
                    Text(L("ライセンスを有効化"))
                        .font(.title2.bold())
                    Text(L("購入後に届いたライセンスキーを入力してください。"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    NSWorkspace.shared.open(PurchaseConfig.purchaseURL)
                } label: {
                    HStack(spacing: 4) {
                        Text(L("ライセンスをお持ちでない方は"))
                            .foregroundStyle(.secondary)
                        Text(L("購入する"))
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
                                Text(L("有効化する"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || gate.isActivating)
                    .frame(maxWidth: 260)

                    Button(L("キャンセル")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .frame(width: 420)
        .onDisappear { gate.licenseError = nil }
    }

    private func activate() async {
        await gate.activateLicense(key: key.trimmingCharacters(in: .whitespaces))
        if gate.status == .licensed { activated = true }
    }
}
