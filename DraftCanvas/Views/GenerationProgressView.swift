import SwiftUI

struct GenerationProgressView: View {
    let prompt: String
    let seed: Int
    let phase: CodexGenerationPhase
    @State private var isHovering = false
    @State private var showPromptOverlay = false
    @State private var promptDelayTask: Task<Void, Never>?
    @State private var visibleBlobCount: Int = 1
    @State private var blobTimer: Task<Void, Never>?

    private func blobCountForPhase(_ p: CodexGenerationPhase) -> Int {
        switch p {
        case .queued: return 1
        case .reasoning: return 2
        case .imageGen: return 3
        }
    }

    var body: some View {
        AuroraPlaceholderView(seed: seed, visibleBlobCount: visibleBlobCount)
        .overlay(alignment: .bottom) {
            if showPromptOverlay && !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 6,
                            bottomTrailingRadius: 6,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showPromptOverlay)
        .animation(.easeIn(duration: 1.2), value: visibleBlobCount)
        .onAppear {
            visibleBlobCount = blobCountForPhase(phase)
            startBlobTimerIfNeeded()
        }
        .onChange(of: phase) { _, newPhase in
            let target = blobCountForPhase(newPhase)
            if visibleBlobCount < target {
                visibleBlobCount = target
            }
            startBlobTimerIfNeeded()
        }
        .onDisappear {
            blobTimer?.cancel()
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                promptDelayTask?.cancel()
                promptDelayTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled {
                        showPromptOverlay = true
                    }
                }
            } else {
                promptDelayTask?.cancel()
                showPromptOverlay = false
            }
        }
    }

    private func startBlobTimerIfNeeded() {
        guard phase == .imageGen, visibleBlobCount < 5 else { return }
        blobTimer?.cancel()
        blobTimer = Task {
            while !Task.isCancelled, visibleBlobCount < 5 {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    if visibleBlobCount < 5 { visibleBlobCount += 1 }
                }
            }
        }
    }
}
