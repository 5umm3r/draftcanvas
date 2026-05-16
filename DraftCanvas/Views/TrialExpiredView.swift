import SwiftUI

struct TrialExpiredView: View {
    @StateObject private var gate = EntitlementGate.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(L("トライアル期間が終了しました"))
                    .font(.title2.bold())
                Text(L("引き続きご利用いただくには\nDraft Canvas をご購入ください。"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(PurchaseConfig.purchaseURL)
                } label: {
                    Text(L("購入する"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 260)

                Button(L("ライセンスキーを持っている")) {
                    dismiss()
                    gate.showLicenseSheet = true
                }
                .foregroundStyle(.secondary)

                Button(L("後で")) { dismiss() }
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(40)
        .frame(width: 380)
    }
}
