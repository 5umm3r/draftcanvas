import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @EnvironmentObject private var viewModel: DraftCanvasViewModel

    var body: some View {
        Form {
            Picker("言語", selection: Binding(
                get: { l10n.current },
                set: { l10n.current = $0 }
            )) {
                ForEach(LocalizationManager.AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("保存先") {
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
                    Spacer()
                    Button("変更…") { viewModel.chooseSaveFolder() }
                }
            }
        }
        .padding()
        .frame(width: 400)
        .alert("再起動が必要", isPresented: $l10n.pendingRestart) {
            Button("終了") { NSApp.terminate(nil) }
            Button("後で", role: .cancel) {}
        } message: {
            Text("変更を反映するには Draft Canvas を再起動してください")
        }
    }
}
