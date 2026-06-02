import SwiftUI

private struct TopBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TopBarButtonLabel(configuration: configuration)
    }
    private struct TopBarButtonLabel: View {
        let configuration: Configuration
        @State private var isHovered = false
        var body: some View {
            configuration.label
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .opacity(isHovered || configuration.isPressed ? 1.0 : 0.55)
                .onHover { isHovered = $0 }
        }
    }
}

private struct TopBarMenuIconModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .opacity(isHovered ? 1.0 : 0.55)
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func topBarMenuIconStyle() -> some View { modifier(TopBarMenuIconModifier()) }
}

extension ContentView {
    private var accountButtonSymbol: String {
        if viewModel.accountUsageStatus.accountKind == .unauthenticated {
            return "person.crop.circle.badge.minus"
        } else if viewModel.accountUsagePrewarmFailed {
            return "person.crop.circle.badge.exclamationmark"
        } else {
            return "person.crop.circle"
        }
    }

    var topStatusBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleLogWindow) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(TopBarButtonStyle())
            .help("ログ")
            .accessibilityLabel("ログ")

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
                Image(systemName: viewModel.completionSound == CompletionSoundOption.off.rawValue
                    ? "speaker.slash"
                    : "speaker.wave.2")
                    .font(.body.weight(.semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .topBarMenuIconStyle()
            .help("完了音")
            .accessibilityLabel("完了音")

            Button {
                viewModel.cycleAppearance()
            } label: {
                Image(systemName: AppAppearance(rawValue: viewModel.appAppearanceRaw)?.systemImage ?? "sun.max")
                    .font(.body)
            }
            .buttonStyle(TopBarButtonStyle())
            .help("テーマ切替")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .buttonStyle(TopBarButtonStyle())
            .help("設定")
            .accessibilityLabel("設定")

            Spacer(minLength: 16)

            if viewModel.accountUsageStatus.shouldShowUsagePills {
                usagePill(
                    prefix: viewModel.accountUsageStatus.primaryUsagePrefix,
                    percentLabel: viewModel.accountUsageStatus.primaryUsagePercentLabel,
                    remainingFraction: viewModel.accountUsageStatus.primaryUsageRemainingFraction,
                    resetText: viewModel.accountUsageStatus.primaryResetText
                )
                usagePill(
                    prefix: viewModel.accountUsageStatus.secondaryUsagePrefix,
                    percentLabel: viewModel.accountUsageStatus.secondaryUsagePercentLabel,
                    remainingFraction: viewModel.accountUsageStatus.secondaryUsageRemainingFraction,
                    resetText: viewModel.accountUsageStatus.secondaryResetText
                )
            }

            Button {
                viewModel.refreshAccountUsage()
            } label: {
                if viewModel.isRefreshingAccountUsage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
            }
            .buttonStyle(TopBarButtonStyle())
            .help("アカウントと使用量を更新")
            .disabled(viewModel.isRefreshingAccountUsage || !viewModel.generatingProjectIDs.isEmpty)

            Button {
                isAccountPopoverPresented.toggle()
            } label: {
                Image(systemName: accountButtonSymbol)
                    .font(.body)
            }
            .buttonStyle(TopBarButtonStyle())
            .help("アカウント")
            .accessibilityLabel("アカウント")
            .popover(isPresented: $isAccountPopoverPresented, arrowEdge: .bottom) {
                AccountPopover(
                    status: viewModel.accountUsageStatus,
                    isLoading: viewModel.isRefreshingAccountUsage,
                    hasFailed: viewModel.accountUsagePrewarmFailed,
                    codexVersion: viewModel.codexVersion,
                    onRetry: viewModel.refreshAccountUsage,
                    onRelaunchAndRetry: viewModel.relaunchAndRefreshAccountUsage
                )
                .environment(\.locale, l10n.locale)
                .environmentObject(l10n)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.regularMaterial)
    }

    func usagePill(
        prefix: String,
        percentLabel: String,
        remainingFraction: Double?,
        resetText: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary)

                usageProgressBar(value: remainingFraction)
            }

            Text(percentLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()

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
        let barColor: Color = {
            guard value != nil else { return .clear }
            if progress > 0.5 { return .green }
            if progress > 0.2 { return .orange }
            return .red
        }()

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.12))

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor.opacity(0.82))
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
