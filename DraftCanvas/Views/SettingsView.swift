import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var viewModel: DraftCanvasViewModel

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: 12,
             verticalSpacing: 14) {
            GridRow {
                Text("言語")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: Binding(
                        get: { l10n.current },
                        set: { l10n.current = $0 }
                    )) {
                        ForEach(LocalizationManager.AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: { EmptyView() }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                    Text("変更には再起動が必要です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .gridColumnAlignment(.leading)
            }
            GridRow {
                Text("生成指示を英語に翻訳")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $viewModel.translateToEnglish) { EmptyView() }
                        .labelsHidden()
                        .toggleStyle(.switch)
                    Text("オンにすると生成前に英語へ翻訳しブレを抑えますが、トークン消費が増えます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }
            GridRow {
                Text("保存先")
                HStack(spacing: 8) {
                    if let url = viewModel.preferredSaveFolder {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(NSString(string: url.path).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未選択")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("変更…") { viewModel.chooseSaveFolder() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("再起動が必要", isPresented: $l10n.pendingRestart) {
            if viewModel.hasInFlightWork {
                Button("中断して再起動", role: .destructive) {
                    Task { @MainActor in
                        await viewModel.prepareForRelaunch()
                        l10n.relaunch()
                    }
                }
            } else {
                Button("再起動") { l10n.relaunch() }
            }
            Button("後で", role: .cancel) {}
        } message: {
            if viewModel.hasInFlightWork {
                Text("進行中の作業（生成・書き出し等）があります。中断して再起動すると、これらは破棄されます。")
            } else {
                Text("変更を反映するには Draft Canvas を再起動します")
            }
        }
    }
}
