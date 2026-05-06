import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ImageCreatorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            topStatusBar

            Divider()

            HStack(spacing: 0) {
                toolRail
                canvasArea
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

            usagePill(systemName: "clock", label: viewModel.accountUsageStatus.primaryUsageLabel)
            usagePill(systemName: "calendar", label: viewModel.accountUsageStatus.secondaryUsageLabel)

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

    private func usagePill(systemName: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(Capsule())
    }

    private var canvasArea: some View {
        ZStack(alignment: .bottom) {
            canvas

            promptPanel
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
    }

    private var toolRail: some View {
        VStack(spacing: 14) {
            toolButton(systemName: "cursorarrow", selected: true)
            toolButton(systemName: "photo", selected: viewModel.outputMode == .raster) {
                viewModel.outputMode = .raster
            }
            toolButton(systemName: "wand.and.stars", selected: viewModel.transparentBackground) {
                viewModel.transparentBackground.toggle()
            }
            toolButton(systemName: "curlybraces", selected: viewModel.outputMode == .svg) {
                viewModel.outputMode = .svg
            }

            Divider()
                .frame(width: 44)
                .padding(.vertical, 4)

            toolButton(systemName: "square.and.arrow.down") {
                viewModel.saveSelected()
            }
            toolButton(systemName: "tray.and.arrow.down") {
                viewModel.saveAll()
            }

            Spacer()

            toolButton(systemName: "stop.circle") {
                viewModel.stopServer()
            }
        }
        .padding(.vertical, 18)
        .frame(width: 74)
        .background(.white.opacity(0.86))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
        }
    }

    private func toolButton(
        systemName: String,
        selected: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(selected ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(selected ? Color.black : Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private func preview(for job: GenerationJob) -> some View {
        if let imageData = job.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else if let svgText = job.svgText {
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
            Text("Details")
                .font(.headline)

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

                Text("Job Log")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(job.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                Text("生成結果を選択すると詳細を表示します。")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("App Log")
                .font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.logs.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
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

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }

    private var promptPanel: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 18))
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .overlay(alignment: .topLeading) {
                    if viewModel.prompt.isEmpty {
                        Text("Describe what you want to generate")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 21)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            HStack(spacing: 14) {
                Picker("Mode", selection: $viewModel.outputMode) {
                    ForEach(GenerationOutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Toggle("Transparent", isOn: $viewModel.transparentBackground)
                    .toggleStyle(.checkbox)

                Stepper("Count \(viewModel.count)", value: $viewModel.count, in: 1...24)
                    .frame(width: 115)

                Stepper("Parallel \(viewModel.concurrency)", value: $viewModel.concurrency, in: 1...8)
                    .frame(width: 135)

                Spacer()

                Button {
                    viewModel.saveSelected()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedJob == nil)

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
