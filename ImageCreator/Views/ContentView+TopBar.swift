import SwiftUI

extension ContentView {
    var topStatusBar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.chooseSaveFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.body.weight(.semibold))
                    Text("保存先")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)
            .help("保存先フォルダ: \(viewModel.preferredSaveFolderLabel)")

            Button(action: toggleLogWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.body.weight(.semibold))
                    Text("ログ")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)

            Menu {
                Button {
                    viewModel.completionSound = CompletionSoundOption.off.rawValue
                } label: {
                    HStack {
                        Text(CompletionSoundOption.off.displayName)
                        if viewModel.completionSound == CompletionSoundOption.off.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(CompletionSoundOption.allCases.filter { $0 != .off }, id: \.self) { option in
                    Button {
                        viewModel.completionSound = option.rawValue
                        NSSound(named: NSSound.Name(option.rawValue))?.play()
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if viewModel.completionSound == option.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.completionSound == CompletionSoundOption.off.rawValue
                        ? "speaker.slash"
                        : "speaker.wave.2")
                        .font(.body.weight(.semibold))
                    Text("完了音")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("完了通知サウンド: \(CompletionSoundOption(rawValue: viewModel.completionSound)?.displayName ?? viewModel.completionSound)")

            Spacer(minLength: 16)

            Button {
                showCountPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.totalGeneratedImages)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("生成枚数の詳細")
            .popover(isPresented: $showCountPopover, arrowEdge: .bottom) {
                GenerationCountPopover(viewModel: viewModel)
            }

            usagePill(
                systemName: "clock",
                label: viewModel.accountUsageStatus.primaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.primaryUsageRemainingFraction,
                resetText: viewModel.accountUsageStatus.primaryResetText
            )
            usagePill(
                systemName: "calendar",
                label: viewModel.accountUsageStatus.secondaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.secondaryUsageRemainingFraction,
                resetText: viewModel.accountUsageStatus.secondaryResetText
            )

            Button {
                viewModel.refreshAccountUsage()
            } label: {
                if viewModel.isRefreshingAccountUsage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .help("アカウントと使用量を更新")
            .disabled(viewModel.isRefreshingAccountUsage)

            Divider()
                .frame(height: 22)

            Button {
                isAccountPopoverPresented.toggle()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isAccountPopoverPresented, arrowEdge: .bottom) {
                AccountPopover(
                    status: viewModel.accountUsageStatus,
                    isLoading: viewModel.isRefreshingAccountUsage,
                    hasFailed: viewModel.accountUsagePrewarmFailed,
                    isLoggingOut: viewModel.isLoggingOut,
                    codexVersion: viewModel.codexVersion,
                    onRetry: viewModel.refreshAccountUsage,
                    onLogout: viewModel.logout
                )
            }

            Divider()
                .frame(height: 20)

            Button {
                viewModel.cycleAppearance()
            } label: {
                Image(systemName: AppAppearance(rawValue: viewModel.appAppearanceRaw)?.systemImage ?? "sun.max")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("テーマ切替")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.regularMaterial)
    }

    func usagePill(
        systemName: String,
        label: String,
        remainingFraction: Double?,
        resetText: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()

            usageProgressBar(value: remainingFraction)

            if let resetText {
                Text(resetText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(Capsule())
    }

    func usageProgressBar(value: Double?) -> some View {
        let progress = min(1, max(0, value ?? 0))

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.12))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(value == nil ? 0 : 0.82))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(width: 52, height: 4)
        .accessibilityHidden(true)
    }

    func toggleLogWindow() {
        if isLogWindowVisible {
            dismissWindow(id: "logs")
        } else {
            openWindow(id: "logs")
        }
        isLogWindowVisible.toggle()
    }
}
