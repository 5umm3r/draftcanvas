import SwiftUI
import AppKit

struct PromptCopyButton: View {
    let prompt: String
    @State private var didCopy = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(prompt, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.2)) { didCopy = false }
            }
        } label: {
            if didCopy {
                Text("Copied!")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help("プロンプトをコピー")
    }
}
