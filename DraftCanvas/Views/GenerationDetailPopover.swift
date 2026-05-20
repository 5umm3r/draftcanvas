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

            Spacer()
        }
        .padding(18)
        .frame(width: 320, height: 400)
    }
}
