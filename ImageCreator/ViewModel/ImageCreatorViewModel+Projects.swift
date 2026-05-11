import Foundation

extension ImageCreatorViewModel {
    @discardableResult
    func createProject(initialName: String? = nil, resetInputs: Bool = true) -> Project {
        let name = initialName ?? ProjectNaming.defaultName()
        let project = Project(name: name, isAutoNamed: true)
        projects.append(project)
        if resetInputs {
            var inputs = ProjectInputs()
            if let defaultModel = availableModels.first(where: \.isDefault) ?? availableModels.first {
                inputs.model = defaultModel.id
            }
            inputsByProject[project.id] = inputs
        } else {
            inputsByProject[project.id] = draftInputs
            draftInputs = ProjectInputs()
        }
        selectedProjectID = project.id  // didSet → saveState
        return project
    }

    func renameProject(id: UUID, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].name = trimmed.isEmpty ? ProjectNaming.defaultName() : trimmed
        projects[index].isAutoNamed = false
        projects[index].updatedAt = Date()
        saveState()
    }

    func deleteProject(id: UUID) {
        for item in items where item.projectID == id {
            projectStore.deleteItemFile(item)
        }
        items.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        inputsByProject.removeValue(forKey: id)
        jobsByProject.removeValue(forKey: id)
        generatingProjectIDs.remove(id)
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id  // didSet → saveState
        } else {
            saveState()
        }
    }
}
