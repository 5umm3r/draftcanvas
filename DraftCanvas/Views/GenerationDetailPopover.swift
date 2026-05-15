import SwiftUI

struct GenerationDetailPopover: View {
    let job: GenerationJob
    @ObservedObject var viewModel: DraftCanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("詳細")
                .font(.headline)

            DetailRow(label: "Status", value: job.status.title)
            DetailRow(label: "Prompt", value: job.prompt)

            if let revisedPrompt = job.revisedPrompt {
                DetailRow(label: "Revised", value: revisedPrompt)
            }
            if let errorMessage = job.errorMessage {
                DetailRow(label: "Error", value: errorMessage)
            }

            Divider()

            PopoverButton(systemImage: "square.and.arrow.up", title: L("エクスポート")) {
                guard EntitlementGate.shared.requireUnlocked() else { return }
                viewModel.exportSelected()
            }
            .disabled(job.status != .succeeded)

            Spacer()
        }
        .padding(18)
        .frame(width: 320, height: 400)
    }
}
