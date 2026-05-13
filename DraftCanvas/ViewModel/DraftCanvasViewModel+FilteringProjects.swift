import Foundation

extension DraftCanvasViewModel {
    func createFilteringProject(name: String, searchQuery: String) {
        let filtering = FilteringProject(name: name, searchQuery: searchQuery)
        filteringProjects.append(filtering)
        saveState()
        selectedFilteringProjectID = filtering.id
    }

    func updateFilteringProject(id: UUID, name: String, searchQuery: String) {
        guard let idx = filteringProjects.firstIndex(where: { $0.id == id }) else { return }
        filteringProjects[idx].name = name
        filteringProjects[idx].searchQuery = searchQuery
        filteringProjects[idx].updatedAt = Date()
        saveState()
    }

    func saveCurrentSearchAsFilteringProject(thenSelect destination: SidebarSelection? = nil) {
        let q = sidebarSearchCommitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let fp = FilteringProject(name: q, searchQuery: q)
        filteringProjects.append(fp)
        saveState()
        exitSearchMode(clearDraft: true)
        sidebarSelection = destination ?? .filtering(fp.id)
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
