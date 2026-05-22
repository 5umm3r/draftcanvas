import SwiftUI

struct JobPreviewView: View {
    let job: GenerationJob
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else if job.status == .failed {
                VStack(spacing: 8) {
                    switch job.failureKind {
                    case .rateLimited:
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)
                        Text(String(localized: "並列失敗"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    case .timeout:
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)
                        Text(String(localized: "タイムアウト"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    default:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)
                    }
                    if let message = job.errorMessage {
                        Text(message)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    }
                }
            } else {
                GenerationProgressView(prompt: job.prompt, seed: job.index)
            }
        }
        .task(id: job.imageData) {
            guard let data = job.imageData else { nsImage = nil; return }
            nsImage = await Task.detached(priority: .utility) { NSImage(data: data) }.value
        }
    }
}
