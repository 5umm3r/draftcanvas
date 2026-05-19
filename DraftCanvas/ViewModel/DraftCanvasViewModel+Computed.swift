import SwiftUI

extension DraftCanvasViewModel {
    var effectiveProjectID: UUID? { activeEditProjectID ?? selectedProjectID }

    var currentInputs: ProjectInputs {
        if let id = effectiveProjectID, let inputs = inputsByProject[id] {
            return inputs
        }
        return draftInputs
    }

    var currentJobs: [GenerationJob] {
        effectiveProjectID.flatMap { jobsByProject[$0] } ?? []
    }

    var isGeneratingForSelected: Bool {
        effectiveProjectID.map { generatingProjectIDs.contains($0) } ?? false
    }

    func binding<T>(for keyPath: WritableKeyPath<ProjectInputs, T>) -> Binding<T> {
        Binding(
            get: { self.currentInputs[keyPath: keyPath] },
            set: { newValue in
                if let id = self.effectiveProjectID {
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


    var isEditingHistoryItem: Bool {
        currentInputs.editSource != nil
    }

    var selectedModelCostLevel: Int {
        let modelID = currentInputs.model
        guard !modelID.isEmpty,
              let model = availableModels.first(where: { $0.id == modelID }) else { return 0 }
        return model.rating?.costLevel ?? 0
    }

    var itemActionCostLevel: Int {
        guard !availableModels.isEmpty else { return 0 }
        let model = Self.selectFastLowCostModel(from: availableModels)
        return model.rating?.costLevel ?? 0
    }

    var canGenerate: Bool {
        !currentInputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func itemsMatching(searchQuery: String) -> [ProjectItem] {
        let tokens = searchQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        return items.filter { item in
            tokens.allSatisfy { token in
                item.tags.contains(where: { $0.localizedCaseInsensitiveContains(token) })
                || item.prompt.localizedCaseInsensitiveContains(token)
                || (item.revisedPrompt?.localizedCaseInsensitiveContains(token) ?? false)
            }
        }
    }

    func itemsMatchingFiltering(_ filtering: FilteringProject) -> [ProjectItem] {
        itemsMatching(searchQuery: filtering.searchQuery)
    }

    var displayedItems: [ProjectItem] {
        if isSearchActive {
            let matched = itemsMatching(searchQuery: sidebarSearchCommitted)
            switch canvasSortOrder {
            case .createdAtAscending: return matched.sorted { $0.createdAt < $1.createdAt }
            case .createdAtDescending: return matched.sorted { $0.createdAt > $1.createdAt }
            }
        }
        if isAllImagesSelected {
            switch canvasSortOrder {
            case .createdAtAscending: return items.sorted { $0.createdAt < $1.createdAt }
            case .createdAtDescending: return items.sorted { $0.createdAt > $1.createdAt }
            }
        }
        if let filteringID = selectedFilteringProjectID,
           let filtering = filteringProjects.first(where: { $0.id == filteringID }) {
            let matched = itemsMatchingFiltering(filtering)
            switch canvasSortOrder {
            case .createdAtAscending: return matched.sorted { $0.createdAt < $1.createdAt }
            case .createdAtDescending: return matched.sorted { $0.createdAt > $1.createdAt }
            }
        }
        return itemsForSelectedProject
    }

    func recomputeDisplayedItems() {
        displayedItemsSnapshot = displayedItems
    }
}
