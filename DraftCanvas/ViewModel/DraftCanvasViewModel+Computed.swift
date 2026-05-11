import SwiftUI

extension DraftCanvasViewModel {
    var currentInputs: ProjectInputs {
        if let id = selectedProjectID, let inputs = inputsByProject[id] {
            return inputs
        }
        return draftInputs
    }

    var currentJobs: [GenerationJob] {
        selectedProjectID.flatMap { jobsByProject[$0] } ?? []
    }

    var isGeneratingForSelected: Bool {
        selectedProjectID.map { generatingProjectIDs.contains($0) } ?? false
    }

    func binding<T>(for keyPath: WritableKeyPath<ProjectInputs, T>) -> Binding<T> {
        Binding(
            get: { self.currentInputs[keyPath: keyPath] },
            set: { newValue in
                if let id = self.selectedProjectID {
                    var inputs = self.inputsByProject[id] ?? ProjectInputs()
                    inputs[keyPath: keyPath] = newValue
                    self.inputsByProject[id] = inputs
                    self.syncProjectModelEffort(for: id, inputs: inputs)
                } else {
                    self.draftInputs[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func syncProjectModelEffort(for projectID: UUID, inputs: ProjectInputs) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard projects[idx].model != inputs.model || projects[idx].reasoningEffort != inputs.reasoningEffort else { return }
        projects[idx].model = inputs.model
        projects[idx].reasoningEffort = inputs.reasoningEffort
        saveState()
    }

    var selectedJob: GenerationJob? {
        guard let selectedJobID else { return currentJobs.first }
        return currentJobs.first { $0.id == selectedJobID }
    }

    var itemsForSelectedProject: [ProjectItem] {
        guard let selectedProjectID else { return [] }
        let filtered = items.filter { $0.projectID == selectedProjectID }
        switch canvasSortOrder {
        case .createdAtAscending:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .createdAtDescending:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var preferredSaveFolderLabel: String {
        preferredSaveFolder?.lastPathComponent ?? "未選択"
    }

    var isEditingHistoryItem: Bool {
        currentInputs.editSource != nil
    }

    var canGenerate: Bool {
        !currentInputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGeneratingForSelected
    }

    var preferredColorScheme: ColorScheme {
        (AppAppearance(rawValue: appAppearanceRaw) ?? .light).colorScheme
    }

    func cycleAppearance() {
        let current = AppAppearance(rawValue: appAppearanceRaw) ?? .light
        appAppearanceRaw = current.next.rawValue
    }

    var favoriteProjects: [Project] {
        projects.filter { $0.isFavorite }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var regularProjects: [Project] {
        projects.filter { !$0.isFavorite }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var allTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }

    func itemsMatchingSmart(_ smart: SmartProject) -> [ProjectItem] {
        guard !smart.tagConditions.isEmpty else { return [] }
        return items.filter { item in
            smart.tagConditions.allSatisfy { item.tags.contains($0) }
        }
    }

    var displayedItems: [ProjectItem] {
        if let smartID = selectedSmartProjectID,
           let smart = smartProjects.first(where: { $0.id == smartID }) {
            let matched = itemsMatchingSmart(smart)
            switch canvasSortOrder {
            case .createdAtAscending: return matched.sorted { $0.createdAt < $1.createdAt }
            case .createdAtDescending: return matched.sorted { $0.createdAt > $1.createdAt }
            }
        }
        return itemsForSelectedProject
    }
}
