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

    var isEditSourceGenerating: Bool {
        currentInputs.editSource != nil && isGeneratingForSelected
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

    private func sortedByDate(_ items: [ProjectItem]) -> [ProjectItem] {
        switch canvasSortOrder {
        case .createdAtAscending: items.sorted { $0.createdAt < $1.createdAt }
        case .createdAtDescending: items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var itemsForSelectedProject: [ProjectItem] {
        guard let selectedProjectID else { return [] }
        return sortedByDate(items.filter { $0.projectID == selectedProjectID })
    }


    var isEditingHistoryItem: Bool {
        currentInputs.editSource != nil
    }

    var showCostBadge: Bool {
        !availableModels.isEmpty
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
            return sortedByDate(itemsMatching(searchQuery: sidebarSearchCommitted))
        }
        if isAllImagesSelected {
            return sortedByDate(items)
        }
        if let filteringID = selectedFilteringProjectID,
           let filtering = filteringProjects.first(where: { $0.id == filteringID }) {
            return sortedByDate(itemsMatchingFiltering(filtering))
        }
        return itemsForSelectedProject
    }

    func recomputeDisplayedItems() {
        displayedItemsSnapshot = displayedItems
    }
}
