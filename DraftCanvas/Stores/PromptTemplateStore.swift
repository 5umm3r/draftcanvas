import Foundation

final class PromptTemplateStore {
    private let fileURL: URL
    private let isInUbiquityContainer: Bool

    init(rootDirectory: URL = ProjectStore.defaultRootDirectory()) {
        self.fileURL = rootDirectory.appendingPathComponent("prompt_templates.json")
        self.isInUbiquityContainer = rootDirectory.path.contains("/Mobile Documents/")
            || rootDirectory.path.contains("/CloudDocs/")
    }

    func load() -> [PromptTemplate] {
        guard let data = coordinatedRead() else { return [] }
        return (try? JSONDecoder().decode([PromptTemplate].self, from: data)) ?? []
    }

    func save(_ templates: [PromptTemplate]) {
        let userTemplates = templates.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(userTemplates) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        coordinatedWrite(data)
    }

    private func coordinatedRead() -> Data? {
        guard isInUbiquityContainer else {
            return try? Data(contentsOf: fileURL)
        }
        var result: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    private func coordinatedWrite(_ data: Data) {
        guard isInUbiquityContainer else {
            try? data.write(to: fileURL, options: .atomic)
            return
        }
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &error) { url in
            try? data.write(to: url, options: .atomic)
        }
    }
}
