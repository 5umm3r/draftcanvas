import Foundation

extension DraftCanvasViewModel {
    func createSmartProject(name: String, tags: [String]) {
        let smart = SmartProject(name: name, tagConditions: tags)
        smartProjects.append(smart)
        saveState()
        selectedSmartProjectID = smart.id
    }

    func updateSmartProject(id: UUID, name: String, tags: [String]) {
        guard let idx = smartProjects.firstIndex(where: { $0.id == id }) else { return }
        smartProjects[idx].name = name
        smartProjects[idx].tagConditions = tags
        smartProjects[idx].updatedAt = Date()
        saveState()
    }

    func deleteSmartProject(id: UUID) {
        smartProjects.removeAll { $0.id == id }
        if selectedSmartProjectID == id { selectedSmartProjectID = nil }
        saveState()
    }

    func selectSmartProject(id: UUID) {
        selectedSmartProjectID = id
        if selectedProjectID != nil {
            selectedProjectID = nil
        }
    }
}
