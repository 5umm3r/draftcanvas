import SwiftUI

private struct AnimationStyleCard: View {
    let style: PlaceholderAnimationStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if style == .random {
                        ZStack {
                            Color(nsColor: .controlBackgroundColor)
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        PlaceholderAnimationView(style: style, seed: 0)
                    }
                }
                .frame(width: 106, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(style.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var viewModel: DraftCanvasViewModel
    @EnvironmentObject private var sparkleUpdater: SparkleUpdaterController
    @State private var showLicenses = false
    @State private var automaticallyChecksForUpdates: Bool = true
    @State private var iCloudPendingRestart = false
    @State private var showDeleteLocalDataAlert = false
    private let animationStyleColumns = [
        GridItem(.fixed(114), spacing: 8),
        GridItem(.fixed(114), spacing: 8),
        GridItem(.fixed(114), spacing: 8),
    ]

    private var selectedAnimationStyle: PlaceholderAnimationStyle {
        PlaceholderAnimationStyle(rawValue: viewModel.placeholderAnimationStyleRaw) ?? .aurora
    }

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
                Text("生成")
                    .gridColumnAlignment(.trailing)
                Toggle(isOn: $viewModel.autoRetryEnabled) {
                    Text("失敗時に自動で再試行（レート制限・タイムアウトのみ）")
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            }
            GridRow {
                Text("アニメーション")
                    .gridColumnAlignment(.trailing)
                LazyVGrid(columns: animationStyleColumns, alignment: .leading, spacing: 6) {
                    ForEach(PlaceholderAnimationStyle.allCases) { style in
                        AnimationStyleCard(
                            style: style,
                            isSelected: style == selectedAnimationStyle
                        ) {
                            viewModel.placeholderAnimationStyleRaw = style.rawValue
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("iCloud")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") },
                        set: { newValue in
                            UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
                            iCloudPendingRestart = true
                        }
                    )) {
                        Text("iCloud Drive で同期")
                    }
                    .toggleStyle(.switch)
                    .disabled(!ICloudSyncMonitor.isICloudAvailable)
                    if !ICloudSyncMonitor.isICloudAvailable {
                        Text("iCloud が利用できません。システム設定で iCloud にサインインしてください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("プロジェクト、画像、設定を iCloud Drive 経由で他の Mac と同期")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if iCloudPendingRestart {
                        Text("変更には再起動が必要です")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if UserDefaults.standard.bool(forKey: "draftcanvas.migration.iCloudSync.v1"),
                       !UserDefaults.standard.bool(forKey: "iCloudLocalDataDeleted") {
                        Button("ローカルデータのコピーを削除") {
                            showDeleteLocalDataAlert = true
                        }
                        .font(.caption)
                    }
                }
                .gridColumnAlignment(.leading)
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
            Button {
                if let url = URL(string: "https://github.com/sponsors/5umm3r") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Support", systemImage: "heart")
            }
            .buttonStyle(.link)
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
        .alert("ローカルデータを削除しますか？", isPresented: $showDeleteLocalDataAlert) {
            Button("削除", role: .destructive) {
                let localRoot = ProjectStore.localDefaultRootDirectory()
                try? FileManager.default.removeItem(at: localRoot)
                UserDefaults.standard.set(true, forKey: "iCloudLocalDataDeleted")
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("iCloud にデータが同期済みの場合のみ実行してください。ローカルコピーを削除します。この操作は取り消せません。")
        }
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
