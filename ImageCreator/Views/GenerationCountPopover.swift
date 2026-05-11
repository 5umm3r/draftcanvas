import SwiftUI

struct GenerationCountPopover: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            countRow(icon: "clock", title: "5h", count: viewModel.session5hCount)
            Divider().padding(.horizontal, 12)
            countRow(icon: "calendar", title: "週次", count: viewModel.sessionWeeklyCount)
            Divider().padding(.horizontal, 12)
            countRow(icon: "photo.stack", title: "累計", count: viewModel.totalGeneratedImages)
            Divider()
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("リセット")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .frame(minWidth: 160)
        .confirmationDialog(
            "すべてのカウンタをリセットしますか？",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("リセット", role: .destructive) { viewModel.resetAllCounters() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("5h・週次・累計すべて 0 になります。元に戻せません。")
        }
    }

    @ViewBuilder
    private func countRow(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
                .font(.subheadline.weight(.semibold))
            Text("枚")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
