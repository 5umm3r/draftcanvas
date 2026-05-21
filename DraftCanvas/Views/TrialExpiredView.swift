import SwiftUI

struct TrialExpiredView: View {
    @ObservedObject private var gate = EntitlementGate.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text(String(localized: "トライアル期間が終了しました"))
                    .font(.title2.bold())
                Text(String(localized: "引き続きご利用いただくには\nDraft Canvas をご購入ください。"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(PurchaseConfig.purchaseURL)
                } label: {
                    Text(String(localized: "購入する"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 260)

                Button(String(localized: "ライセンスキーを持っている")) {
                    dismiss()
                    gate.showLicenseSheet = true
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(width: 380)
    }
}
