import SwiftUI

struct ProjectRow: View {
    let project: Project
    let isEditing: Bool
    let isGenerating: Bool
    @Binding var renamingText: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onStop: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        if isEditing {
            TextField("プロジェクト名", text: $renamingText, onCommit: onCommitRename)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { onCancelRename() }
                .onAppear { isFocused = true }
        } else {
            HStack(spacing: 6) {
                Text(project.name)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isGenerating {
                    if isHovering {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }
}
