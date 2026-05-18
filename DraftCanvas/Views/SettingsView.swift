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
                    .gridColumnAlignment(.leading)
            }
            GridRow {
                Text("生成指示の言語")
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: Binding(
                        get: { viewModel.promptLanguageMode },
                        set: { viewModel.promptLanguageMode = $0 }
                    )) {
                        ForEach(PromptLanguageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: { EmptyView() }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180, alignment: .leading)
                    Text(PromptLanguageMode.settingDescription)
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
            Button("終了") { NSApp.terminate(nil) }
            Button("後で", role: .cancel) {}
        } message: {
            Text("変更を反映するには Draft Canvas を再起動してください")
        }
    }
}
