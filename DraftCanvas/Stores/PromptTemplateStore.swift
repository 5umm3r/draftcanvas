import Foundation

final class PromptTemplateStore: JSONFileStore {
    typealias Payload = [PromptTemplate]

    var fileURL: URL {
        ProjectStore.defaultRootDirectory()
            .appendingPathComponent("prompt_templates.json")
    }

    private var userTemplates: [PromptTemplate]

    init() {
        self.userTemplates = []
        self.userTemplates = (load() ?? []).filter { !$0.isBuiltIn }
    }

    /// 同梱プリセット + ユーザー作成（プリセットが先頭）
    var allTemplates: [PromptTemplate] {
        BuiltInPromptTemplates.all + userTemplates
    }

    func add(_ template: PromptTemplate) {
        var t = template
        // ユーザー作成は必ず isBuiltIn = false
        t = PromptTemplate(
            id: t.id, name: t.name, prompt: t.prompt, isBuiltIn: false,
            count: t.count, aspectRatio: t.aspectRatio, model: t.model, reasoningEffort: t.reasoningEffort
        )
        userTemplates.append(t)
        save(userTemplates)
    }

    func update(_ template: PromptTemplate) {
        guard !template.isBuiltIn,
              let idx = userTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        userTemplates[idx] = template
        save(userTemplates)
    }

    func delete(id: UUID) {
        // builtIn は削除不可
        guard let idx = userTemplates.firstIndex(where: { $0.id == id }) else { return }
        userTemplates.remove(at: idx)
        save(userTemplates)
    }
}
