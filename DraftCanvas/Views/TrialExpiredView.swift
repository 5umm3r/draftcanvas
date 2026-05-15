import SwiftUI

struct TrialExpiredView: View {
    @StateObject private var gate = EntitlementGate.shared
    @Environment(\.dismiss) private var dismiss

    // P4: Lemon Squeezy 商品登録後にここを設定
    private let purchaseURL = URL(string: "https://draftcanvas.lemonsqueezy.com/checkout/buy/2330d4a5-c212-4248-8053-07993e8522e4")!

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("トライアル期間が終了しました")
                    .font(.title2.bold())
                Text("引き続きご利用いただくには\nDraft Canvas をご購入ください。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(purchaseURL)
                } label: {
                    Text("購入する ($29)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 260)

                Button("ライセンスキーを持っている") {
                    dismiss()
                    gate.showLicenseSheet = true
                }
                .foregroundStyle(.secondary)

                Button("後で") { dismiss() }
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(40)
        .frame(width: 380)
    }
}
