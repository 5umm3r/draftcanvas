import SwiftUI

struct ExportOptionsSheet: View {
    @StateObject private var vm: ExportOptionsViewModel
    let saveFolderName: String?
    let onExport: (ExportSettings) -> Void
    let onCancel: () -> Void
    let onChangeSaveFolder: (() -> Void)?

    init(
        request: ExportRequest,
        saveFolderName: String?,
        onExport: @escaping (ExportSettings) -> Void,
        onCancel: @escaping () -> Void,
        onChangeSaveFolder: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: ExportOptionsViewModel(request: request))
        self.saveFolderName = saveFolderName
        self.onExport = onExport
        self.onCancel = onCancel
        self.onChangeSaveFolder = onChangeSaveFolder
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    formatCard
                    resizeCard
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480)
        .onAppear {
            if vm.request.hasVectorSVG {
                vm.format = .svg
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Group {
                if case .batchItems(let entries) = vm.request.source {
                    Text("エクスポート (\(entries.count)枚)")
                } else {
                    Text("エクスポート")
                }
            }
            .font(.headline)
            Spacer()
            Picker("", selection: $vm.format) {
                ForEach(ExportFormat.allCases, id: \.self) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 380)
            .disabled(vm.request.hasVectorSVG)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Format Card

    @ViewBuilder
    private var formatCard: some View {
        switch vm.format {
        case .png:  pngCard
        case .jpeg: jpegCard
        case .svg:  svgCard
        case .tiff: tiffCard
        case .pdf:  pdfCard
        case .webp: webpCard
        }
    }

    private var pngCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("最適化", isOn: $vm.pngOptimize)
                    .toggleStyle(.switch)
                if vm.pngOptimize {
                    Picker("", selection: $vm.pngLevel) {
                        ForEach(PNGOptimizationLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    if vm.pngLevel.isLossy {
                        Label("色数を削減します。画質が一部低下する場合があります", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("ロスレス圧縮（画質変化なし）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var jpegCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("品質")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $vm.jpegQuality) {
                    ForEach(JPEGQualityPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                Text("背景は白に合成されます（JPEGは透過非対応）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var svgCard: some View {
        OptionCard {
            HStack(spacing: 8) {
                Image(systemName: vm.request.hasVectorSVG ? "point.3.connected.trianglepath.dotted" : "photo")
                    .foregroundStyle(.secondary)
                if vm.request.hasVectorSVG {
                    Text("ベクターSVG出力")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("PNG埋込SVG出力")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tiffCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 12) {
                dpiRow
                Text("LZW可逆圧縮・透過（アルファ）保持")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var webpCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("品質")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $vm.webpQuality) {
                    ForEach(WebPQualityPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                Text("透過（アルファチャンネル）を保持します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pdfCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 12) {
                dpiRow
                VStack(alignment: .leading, spacing: 6) {
                    Text("画像圧縮")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $vm.pdfCompression) {
                        ForEach(PDFImageCompression.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    @ViewBuilder
    private var dpiRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("解像度 (DPI)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $vm.dpi) {
                ForEach(ExportDPI.allCases, id: \.self) { d in
                    Text(d.displayName).tag(d)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Resize Card

    private var resizeCard: some View {
        OptionCard {
            VStack(alignment: .leading, spacing: 12) {
                let svgResizeDisabled = vm.request.hasVectorSVG && vm.format == .svg

                Toggle("リサイズ", isOn: $vm.resizeEnabled)
                    .toggleStyle(.switch)
                    .disabled(svgResizeDisabled)

                if svgResizeDisabled {
                    Text("ベクターSVGはサイズ非依存のためリサイズしません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vm.resizeEnabled && !svgResizeDisabled {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("幅")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            TextField("", text: $vm.widthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: vm.widthText) { vm.userDidChangeWidth() }
                            Text("px")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "link")
                            .foregroundStyle(.tertiary)
                            .font(.caption)

                        HStack(spacing: 4) {
                            Text("高")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            TextField("", text: $vm.heightText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: vm.heightText) { vm.userDidChangeHeight() }
                            Text("px")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("オリジナル: \(vm.origW) × \(vm.origH) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if vm.resizeEnabled && vm.isUpscale {
                        Label("オリジナルサイズ以下を指定してください（アップスケール非対応）", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let isBatch = {
            if case .batchItems = vm.request.source { return true }
            return false
        }()
        return HStack(spacing: 10) {
            if isBatch {
                Text("保存先をダイアログで指定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let name = saveFolderName {
                Button {
                    onChangeSaveFolder?()
                } label: {
                    Label(name, systemImage: "folder")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    onChangeSaveFolder?()
                } label: {
                    Label("保存先を設定", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Button("キャンセル") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("保存") {
                vm.saveSettings()
                onExport(vm.currentSettings)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!vm.isValid)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

// MARK: - Option Card Container

private struct OptionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}
