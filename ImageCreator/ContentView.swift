import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ImageCreatorViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedTab: SidebarTab = .generate
    @State private var isLogWindowVisible = false

    var body: some View {
        VStack(spacing: 0) {
            topStatusBar

            Divider()

            HStack(spacing: 0) {
                toolRail

                if selectedTab == .history {
                    historyArea
                } else {
                    canvasArea
                }

                inspector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1180, minHeight: 760)
        .onDisappear {
            viewModel.stopServer()
        }
    }

    private var topStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Codex")
                    .font(.subheadline.weight(.semibold))
            }

            Divider()
                .frame(height: 22)

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)

                Text(viewModel.accountUsageStatus.accountLabel)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .leading)

                Text(viewModel.accountUsageStatus.planLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 16)

            usagePill(
                systemName: "clock",
                label: viewModel.accountUsageStatus.primaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.primaryUsageRemainingFraction
            )
            usagePill(
                systemName: "calendar",
                label: viewModel.accountUsageStatus.secondaryUsageLabel,
                remainingFraction: viewModel.accountUsageStatus.secondaryUsageRemainingFraction
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
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .help("Codexのアカウントと使用量を更新")
            .disabled(viewModel.isRefreshingAccountUsage)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.white.opacity(0.86))
    }

    private var toolRail: some View {
        VStack(spacing: 10) {
            railButton(.generate)
            railButton(.history)

            Divider()
                .frame(width: 72)
                .padding(.vertical, 4)

            actionRailButton(systemName: "folder", title: "保存先", subtitle: viewModel.preferredSaveFolderLabel) {
                viewModel.chooseSaveFolder()
            }

            actionRailButton(systemName: "doc.text.magnifyingglass", title: "ログ") {
                toggleLogWindow()
            }

            Spacer()

            actionRailButton(systemName: "stop.circle", title: "停止") {
                viewModel.stopServer()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 118)
        .background(.white.opacity(0.86))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
        }
    }

    private func railButton(_ tab: SidebarTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.systemName)
                    .frame(width: 18)
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedTab == tab ? .white : .primary)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(selectedTab == tab ? Color.black : Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionRailButton(
        systemName: String,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: systemName)
                        .frame(width: 18)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 38 : 52, alignment: .leading)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleLogWindow() {
        if isLogWindowVisible {
            dismissWindow(id: "logs")
        } else {
            openWindow(id: "logs")
        }
        isLogWindowVisible.toggle()
    }

    private var canvasArea: some View {
        ZStack(alignment: .bottom) {
            canvas

            promptPanel
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
    }

    private var canvas: some View {
        ZStack {
            Color(red: 0.90, green: 0.90, blue: 0.92)

            if viewModel.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .medium))
                    Text("プロンプトを入力して生成してください")
                        .font(.title3.weight(.semibold))
                    Text("生成結果はこのキャンバスに並びます")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 120)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(220), spacing: 28), count: 3),
                        spacing: 28
                    ) {
                        ForEach(viewModel.jobs) { job in
                            generationCard(job)
                        }
                    }
                    .padding(.top, 72)
                    .padding(.horizontal, 90)
                    .padding(.bottom, 220)
                }
            }
        }
    }

    private var historyArea: some View {
        ZStack {
            Color(red: 0.94, green: 0.94, blue: 0.95)

            if viewModel.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36, weight: .medium))
                    Text("履歴はまだありません")
                        .font(.title3.weight(.semibold))
                    Text("生成が完了するとここに保存されます")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210, maximum: 240), spacing: 22)],
                        spacing: 22
                    ) {
                        ForEach(viewModel.history) { item in
                            historyCard(item)
                        }
                    }
                    .padding(32)
                }
            }
        }
    }

    private func generationCard(_ job: GenerationJob) -> some View {
        Button {
            viewModel.selectedJobID = job.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    checkerboard
                    preview(for: job)
                }
                .frame(width: 220, height: 220)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(viewModel.selectedJobID == job.id ? Color.accentColor : Color.black.opacity(0.10), lineWidth: viewModel.selectedJobID == job.id ? 3 : 1)
                }

                HStack {
                    Text("#\(job.index + 1)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    StatusBadge(status: job.status)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func historyCard(_ item: GenerationHistoryItem) -> some View {
        Button {
            viewModel.selectedHistoryItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    checkerboard
                    preview(for: item)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(viewModel.selectedHistoryItemID == item.id ? Color.accentColor : Color.black.opacity(0.10), lineWidth: viewModel.selectedHistoryItemID == item.id ? 3 : 1)
                }

                Text(item.displayTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)

                HStack {
                    Text(item.outputMode.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Capsule())
                    Spacer()
                    Text(item.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func preview(for job: GenerationJob) -> some View {
        if let imageData = job.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else if let svgText = job.svgText {
            svgPreview(svgText)
        } else if job.status == .failed {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(job.errorMessage ?? "生成に失敗しました")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        } else {
            ProgressView()
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private func preview(for item: GenerationHistoryItem) -> some View {
        let fileURL = viewModel.fileURL(for: item)
        if item.outputMode == .raster, let nsImage = NSImage(contentsOf: fileURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else if let svgText = try? String(contentsOf: fileURL, encoding: .utf8) {
            svgPreview(svgText)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.square")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("プレビューを読み込めません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func svgPreview(_ svgText: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "curlybraces.square")
                .font(.system(size: 34))
            Text(svgText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let side: CGFloat = 18
            for x in stride(from: CGFloat(0), to: size.width, by: side) {
                for y in stride(from: CGFloat(0), to: size.height, by: side) {
                    let isDark = (Int(x / side) + Int(y / side)).isMultiple(of: 2)
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    context.fill(Path(rect), with: .color(isDark ? Color.white : Color.black.opacity(0.045)))
                }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedTab == .history ? "履歴詳細" : "詳細")
                .font(.headline)

            if selectedTab == .history {
                historyInspector
            } else {
                generationInspector
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 300)
        .background(.white.opacity(0.78))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var generationInspector: some View {
        if let job = viewModel.selectedJob {
            detailRow("Status", job.status.title)
            detailRow("Mode", job.svgText == nil ? "PNG" : "SVG")
            detailRow("Prompt", job.prompt)

            if let revisedPrompt = job.revisedPrompt {
                detailRow("Revised", revisedPrompt)
            }

            if let errorMessage = job.errorMessage {
                detailRow("Error", errorMessage)
            }

            Divider()

            Button {
                viewModel.saveSelected()
            } label: {
                Label("選択中の生成物を保存", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(job.status != .succeeded)
        } else {
            Text("生成結果を選択すると詳細を表示します。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historyInspector: some View {
        if let item = viewModel.selectedHistoryItem {
            detailRow("Mode", item.outputMode.title)
            detailRow("Prompt", item.prompt)
            detailRow("Created", item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let revisedPrompt = item.revisedPrompt {
                detailRow("Revised", revisedPrompt)
            }

            if let errorMessage = item.errorMessage {
                detailRow("Error", errorMessage)
            }

            Divider()

            Button {
                viewModel.edit(historyItem: item)
                selectedTab = .generate
            } label: {
                Label("再編集", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                viewModel.reveal(historyItem: item)
            } label: {
                Label("Finderで表示", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("履歴を選択すると詳細を表示します。")
                .foregroundStyle(.secondary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(5)
        }
    }

    private var promptPanel: some View {
        VStack(spacing: 0) {
            if viewModel.isEditingHistoryItem {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Text("履歴を再編集")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("解除") {
                        viewModel.cancelEditingHistoryItem()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.10))

                Divider()
            }

            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 18))
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .overlay(alignment: .topLeading) {
                    if viewModel.prompt.isEmpty {
                        Text("生成したい画像を説明")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 21)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            HStack(spacing: 14) {
                Picker("形式", selection: $viewModel.outputMode) {
                    ForEach(GenerationOutputMode.allCases) { mode in
                        Text(promptPanelModeTitle(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Picker("比率", selection: $viewModel.aspectRatio) {
                    ForEach(GenerationAspectRatio.allCases) { aspectRatio in
                        Text(promptPanelAspectRatioTitle(for: aspectRatio)).tag(aspectRatio)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 126)

                Toggle("背景を透過", isOn: $viewModel.transparentBackground)
                    .toggleStyle(.checkbox)

                Stepper("枚数 \(viewModel.count)", value: $viewModel.count, in: 1...24)
                    .frame(width: 115)

                Stepper("並列 \(viewModel.concurrency)", value: $viewModel.concurrency, in: 1...8)
                    .frame(width: 135)

                Spacer()

                Button {
                    viewModel.generate()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(!viewModel.canGenerate)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: 780)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    private func promptPanelModeTitle(for mode: GenerationOutputMode) -> String {
        switch mode {
        case .raster:
            return "画像"
        case .svg:
            return "SVG"
        }
    }

    private func promptPanelAspectRatioTitle(for aspectRatio: GenerationAspectRatio) -> String {
        "\(aspectRatio.title) \(aspectRatio.value)"
    }

    private func usagePill(systemName: String, label: String, remainingFraction: Double?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()

            usageProgressBar(value: remainingFraction)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(Capsule())
    }

    private func usageProgressBar(value: Double?) -> some View {
        let progress = min(1, max(0, value ?? 0))

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.12))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(value == nil ? 0 : 0.82))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(width: 52, height: 4)
        .accessibilityHidden(true)
    }
}

struct LogWindow: View {
    @ObservedObject var viewModel: ImageCreatorViewModel

    var body: some View {
        HSplitView {
            logPane(title: "App Log", lines: Array(viewModel.logs.suffix(240)))
                .frame(minWidth: 360)

            logPane(title: "Job Log", lines: viewModel.selectedJob?.logs ?? [])
                .frame(minWidth: 320)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 420)
    }

    private func logPane(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if lines.isEmpty {
                        Text("ログはまだありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private enum SidebarTab {
    case generate
    case history

    var title: String {
        switch self {
        case .generate:
            return "生成"
        case .history:
            return "履歴"
        }
    }

    var systemName: String {
        switch self {
        case .generate:
            return "sparkles"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

private struct StatusBadge: View {
    let status: GenerationJobStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .queued:
            return .secondary
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .orange
        }
    }
}
