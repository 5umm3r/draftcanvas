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
    @State private var showPruneOrphansAlert = false
    @State private var showPruneResultAlert = false
    @State private var pruneResultMessage = ""
    // Binding(get:) で UserDefaults を直読みすると SwiftUI が変化を購読できず、
    // 操作しても表示が更新されない。@AppStorage で購読する。
    // Int64 は @AppStorage 非対応のため Int で保持（macOS は 64bit のみ）。
    @AppStorage(ICloudCacheEviction.limitBytesKey)
    private var cacheLimitBytes: Int = Int(ICloudCacheEviction.defaultLimitBytes)
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage(ICloudAutoPullPolicy.userDefaultsKey)
    private var autoPullPolicyRaw: String = ICloudAutoPullPolicy.thumbsOnly.rawValue
    @AppStorage("draftcanvas.migration.iCloudSync.v1") private var didMigrateToICloud = false
    @AppStorage("iCloudLocalDataDeleted") private var didDeleteLocalData = false
    @ObservedObject private var iCloudAvailability = ICloudAvailability.shared
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
                    Picker(selection: $l10n.current) {
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
            GridRow {
                Text("メンテナンス")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Button("不要ファイルを削除…") { showPruneOrphansAlert = true }
                    Text("キャンバスから削除済みのアイテムに紐づく残存ファイルを掃除します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .gridColumnAlignment(.leading)
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
                    Toggle(isOn: $iCloudSyncEnabled) {
                        Text("iCloud Drive で同期")
                    }
                    .toggleStyle(.switch)
                    .disabled(!iCloudAvailability.isAvailable)
                    // 同期の有効化は起動時のコンテナ解決に依存するため再起動が要る
                    .onChange(of: iCloudSyncEnabled) { _, _ in
                        iCloudPendingRestart = true
                    }
                    if !iCloudAvailability.isAvailable {
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
                    Toggle(isOn: Binding(
                        // 未知の rawValue が入っていても load() と同じ既定に倒す
                        get: { (ICloudAutoPullPolicy(rawValue: autoPullPolicyRaw) ?? .thumbsOnly) == .thumbsOnly },
                        set: { autoPullPolicyRaw = ($0 ? ICloudAutoPullPolicy.thumbsOnly : .eager).rawValue }
                    )) {
                        Text("省容量モード (画像はオンデマンド DL)")
                    }
                    .toggleStyle(.switch)
                    .font(.caption)
                    // 方針の切替は start() 前に読まれるため再起動が要る
                    .onChange(of: autoPullPolicyRaw) { _, _ in
                        iCloudPendingRestart = true
                    }
                    Picker(selection: $cacheLimitBytes) {
                        Text("1 GB").tag(1 * 1024 * 1024 * 1024)
                        Text("2 GB").tag(2 * 1024 * 1024 * 1024)
                        Text("5 GB").tag(5 * 1024 * 1024 * 1024)
                        Text("10 GB").tag(10 * 1024 * 1024 * 1024)
                        Text("無制限").tag(0)
                    } label: {
                        Text("ローカルキャッシュ上限")
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    if didMigrateToICloud, !didDeleteLocalData {
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
        .alert("不要ファイルを削除しますか？", isPresented: $showPruneOrphansAlert) {
            Button("削除", role: .destructive) {
                let result = viewModel.pruneOrphanFiles()
                let size = ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)
                pruneResultMessage = "\(result.count) 件・\(size) を削除しました"
                showPruneResultAlert = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("キャンバスから削除済みアイテムに紐づくファイル（画像・SVG・サムネイル・マスク・添付）と、Codex が保存した生成キャッシュ（~/.codex/generated_images/）を削除します。iCloud 同期を使用中の場合は、他デバイスからの変更が全て届いた状態で実行してください。同期途中で実行すると未反映のファイルを誤削除するおそれがあります。この操作は取り消せません。")
        }
        .alert("完了", isPresented: $showPruneResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pruneResultMessage)
        }
        .alert("ローカルデータを削除しますか？", isPresented: $showDeleteLocalDataAlert) {
            Button("削除", role: .destructive) {
                let localRoot = ProjectStore.localDefaultRootDirectory()
                try? FileManager.default.removeItem(at: localRoot)
                didDeleteLocalData = true
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
