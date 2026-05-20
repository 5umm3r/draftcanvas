import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var viewModel: DraftCanvasViewModel
    @EnvironmentObject private var sparkleUpdater: SparkleUpdaterController
    @State private var showLicenses = false
    @State private var automaticallyChecksForUpdates: Bool = true

    var body: some View {
        VStack(spacing: 0) {
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
                        .frame(width: 220, alignment: .leading)
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
                        .frame(maxWidth: 340, alignment: .leading)
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
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("アップデート")
                    .gridColumnAlignment(.trailing)
                HStack {
                    Toggle(isOn: $automaticallyChecksForUpdates) {
                        Text("自動的に確認")
                    }
                    .toggleStyle(.switch)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        sparkleUpdater.updater.automaticallyChecksForUpdates = newValue
                    }
                    Spacer()
                    Button("今すぐ確認") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)
                }
                .frame(maxWidth: .infinity)
                .gridColumnAlignment(.leading)
            }
        }
        .padding(24)
        Divider()
        HStack {
            Button("オープンソースライセンスを表示") { showLicenses = true }
                .buttonStyle(.link)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        } // VStack
        .frame(width: 520)
        .onAppear {
            automaticallyChecksForUpdates =
                sparkleUpdater.updater.automaticallyChecksForUpdates
        }
        .sheet(isPresented: $showLicenses) { LicensesSheet() }
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
