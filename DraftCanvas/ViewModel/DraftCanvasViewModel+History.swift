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
        if let replacer = onReplacePromptText {
            replacer(entry.promptText)
        } else {
            if let id = selectedProjectID {
                inputsByProject[id]?.prompt = entry.promptText
            } else {
                draftInputs.prompt = entry.promptText
            }
        }
        isHistoryPopoverPresented = false
    }
}
