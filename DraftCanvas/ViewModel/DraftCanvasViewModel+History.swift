import Foundation

extension DraftCanvasViewModel {
    func loadHistory() {
        promptHistory = historyStore.load()
    }

    func recordHistory(prompt: String) {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if let idx = promptHistory.firstIndex(where: {
            $0.promptText.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }) {
            var entry = promptHistory.remove(at: idx)
            entry.useCount += 1
            entry.lastUsedAt = Date()
            promptHistory.insert(entry, at: 0)
        } else {
            promptHistory.insert(PromptHistoryEntry(promptText: normalized), at: 0)
            if promptHistory.count > 50 {
                promptHistory.removeLast()
            }
        }
        historyStore.save(promptHistory)
    }

    func deleteHistoryEntry(_ entry: PromptHistoryEntry) {
        promptHistory.removeAll { $0.id == entry.id }
        historyStore.save(promptHistory)
    }

    func clearHistory() {
        promptHistory.removeAll()
        historyStore.save(promptHistory)
    }

    func applyHistory(_ entry: PromptHistoryEntry) {
        if let appender = onAppendPromptText {
            appender(entry.promptText)
        } else {
            if let id = selectedProjectID {
                let existing = inputsByProject[id]?.prompt ?? ""
                inputsByProject[id]?.prompt = PromptTextAppender.smartAppend(existing: existing, addition: entry.promptText)
            } else {
                let existing = draftInputs.prompt
                draftInputs.prompt = PromptTextAppender.smartAppend(existing: existing, addition: entry.promptText)
            }
        }
        shouldFocusPromptAfterApply = true
        isHistoryPopoverPresented = false
    }
}
