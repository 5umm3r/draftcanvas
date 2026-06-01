import Foundation

extension DraftCanvasViewModel {
    func loadTemplates() {
        let userTemplates = templateStore.load()
        templates = PromptTemplate.builtIns + userTemplates
    }

    func addTemplate(name: String, promptText: String) {
        let template = PromptTemplate(name: name, promptText: promptText, category: .user)
        templates.append(template)
        templateStore.save(templates)
    }

    func updateTemplate(_ template: PromptTemplate, name: String, promptText: String) {
        guard !template.isBuiltIn,
              let idx = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[idx].name = name
        templates[idx].promptText = promptText
        templateStore.save(templates)
    }

    func deleteTemplate(_ template: PromptTemplate) {
        guard !template.isBuiltIn else { return }
        templates.removeAll { $0.id == template.id }
        templateStore.save(templates)
    }

    func applyTemplate(_ template: PromptTemplate) {
        if let appender = onAppendPromptText {
            appender(template.promptText)
        } else {
            if let id = selectedProjectID {
                let existing = inputsByProject[id]?.prompt ?? ""
                inputsByProject[id]?.prompt = PromptTextAppender.smartAppend(existing: existing, addition: template.promptText)
            } else {
                let existing = draftInputs.prompt
                draftInputs.prompt = PromptTextAppender.smartAppend(existing: existing, addition: template.promptText)
            }
        }
        shouldFocusPromptAfterApply = true
        isTemplatePopoverPresented = false
    }
}
