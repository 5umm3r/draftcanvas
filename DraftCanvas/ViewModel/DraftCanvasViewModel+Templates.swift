import Foundation

extension DraftCanvasViewModel {
    /// テンプレートを現在の入力欄に適用
    func applyTemplate(_ template: PromptTemplate) {
        binding(for: \.prompt).wrappedValue = template.prompt
        if let count = template.count {
            binding(for: \.count).wrappedValue = count
        }
        if let aspectRatio = template.aspectRatio {
            binding(for: \.aspectRatio).wrappedValue = aspectRatio
        }
        if let model = template.model, availableModels.contains(where: { $0.id == model }) {
            binding(for: \.model).wrappedValue = model
        }
        if let reasoningEffort = template.reasoningEffort {
            binding(for: \.reasoningEffort).wrappedValue = reasoningEffort
        }
    }

    func saveTemplate(_ template: PromptTemplate) {
        promptTemplateStore.add(template)
        promptTemplates = promptTemplateStore.allTemplates
    }

    func updateTemplate(_ template: PromptTemplate) {
        promptTemplateStore.update(template)
        promptTemplates = promptTemplateStore.allTemplates
    }

    func deleteTemplate(id: UUID) {
        promptTemplateStore.delete(id: id)
        promptTemplates = promptTemplateStore.allTemplates
    }
}
