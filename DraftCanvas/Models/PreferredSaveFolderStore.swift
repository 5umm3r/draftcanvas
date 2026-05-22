import Foundation

// MARK: - Persistence helpers

struct PreferredSaveFolderStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "preferredSaveFolderBookmark") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> URL? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale {
            return url
        }

        guard let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func save(_ directory: URL) throws {
        do {
            let data = try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            userDefaults.set(data, forKey: key)
        } catch {
            userDefaults.set(Data(directory.path.utf8), forKey: key)
        }
    }
}
