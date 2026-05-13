import Foundation

extension DraftCanvasViewModel {
    func createFilteringProject(name: String, tags: [String]) {
        let filtering = FilteringProject(name: name, tagConditions: tags)
        filteringProjects.append(filtering)
        saveState()
        selectedFilteringProjectID = filtering.id
    }

    func updateFilteringProject(id: UUID, name: String, tags: [String]) {
        guard let idx = filteringProjects.firstIndex(where: { $0.id == id }) else { return }
        filteringProjects[idx].name = name
        filteringProjects[idx].tagConditions = tags
        filteringProjects[idx].updatedAt = Date()
        saveState()
    }

    func deleteFilteringProject(id: UUID) {
        filteringProjects.removeAll { $0.id == id }
        if selectedFilteringProjectID == id { selectedFilteringProjectID = nil }
        saveState()
    }

    func selectFilteringProject(id: UUID) {
        sidebarSelection = .filtering(id)
    }
}
