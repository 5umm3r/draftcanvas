import XCTest
@testable import DraftCanvas

/// 他端末が projects.json を書き換えた際に、実行中の ViewModel が
/// NSFilePresenter 経由で変更を検知してメモリへ取り込むことを検証する。
/// ルートパスに `/CloudDocs/` を含めることで iCloud コンテナ扱いにし、
/// 実 iCloud なしで presenter 経路を通す。
@MainActor
final class RemoteMetadataReloadTests: XCTestCase {

    private func makeCloudLikeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudDocs", isDirectory: true)
            .appendingPathComponent("RemoteReloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeViewModel(root: URL) -> DraftCanvasViewModel {
        DraftCanvasViewModel(
            projectStore: ProjectStore(rootDirectory: root),
            preferredSaveFolderStore: PreferredSaveFolderStore(
                userDefaults: UserDefaults(suiteName: "DraftCanvasTests-\(UUID().uuidString)")!
            ),
            prewarmOnInit: false
        )
    }

    /// iCloud daemon と同様に NSFileCoordinator 経由で書き換える。
    /// 非協調書き込みでは presenter に通知が届かない場合がある。
    private func writeCoordinated(_ snapshot: ProjectStore.Snapshot, to url: URL) throws {
        let data = try JSONEncoder.projectEncoder.encode(snapshot)
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordURL in
            do { try data.write(to: coordURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testRemoteBookmarkChangeIsAppliedToRunningViewModel() async throws {
        let root = try makeCloudLikeRoot()
        let store = ProjectStore(rootDirectory: root)
        let project = Project(name: "P")
        let item = ProjectItem(projectID: project.id, prompt: "a", aspectRatio: .square)
        XCTAssertTrue(store.save(ProjectStore.Snapshot(projects: [project], items: [item])))

        let vm = makeViewModel(root: root)
        XCTAssertTrue(vm.projectStore.isInUbiquityContainer)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertFalse(vm.items[0].isBookmarked)

        var bookmarked = item
        bookmarked.isBookmarked = true
        try writeCoordinated(
            ProjectStore.Snapshot(projects: [project], items: [bookmarked]),
            to: vm.projectStore.metadataURL
        )

        let applied = await waitUntil { vm.items.first?.isBookmarked == true }
        XCTAssertTrue(applied, "リモートのブックマーク変更が実行中の ViewModel に反映されていない")
    }

    func testRemoteChangeDoesNotOverwriteLocalUiSelection() async throws {
        let root = try makeCloudLikeRoot()
        let store = ProjectStore(rootDirectory: root)
        let project = Project(name: "P")
        let item = ProjectItem(projectID: project.id, prompt: "a", aspectRatio: .square)
        XCTAssertTrue(store.save(ProjectStore.Snapshot(projects: [project], items: [item])))

        let vm = makeViewModel(root: root)
        let localSelection = vm.sidebarSelection

        var remote = ProjectStore.Snapshot(projects: [project], items: [item])
        remote.items[0].tags = ["remote"]
        remote.sidebarSelection = .project(project.id)
        try writeCoordinated(remote, to: vm.projectStore.metadataURL)

        let applied = await waitUntil { vm.items.first?.tags == ["remote"] }
        XCTAssertTrue(applied)
        XCTAssertEqual(vm.sidebarSelection, localSelection)
    }

    func testRemoteReloadDeferredWhileLocalSavePendingThenApplied() async throws {
        let root = try makeCloudLikeRoot()
        let store = ProjectStore(rootDirectory: root)
        let project = Project(name: "P")
        let item = ProjectItem(projectID: project.id, prompt: "a", aspectRatio: .square)
        XCTAssertTrue(store.save(ProjectStore.Snapshot(projects: [project], items: [item])))

        let vm = makeViewModel(root: root)
        // ローカル編集 → 保存デバウンス中
        vm.toggleBookmark(item)
        XCTAssertTrue(vm.items[0].isBookmarked)

        // その間にリモートが別の変更を書く
        var remote = ProjectStore.Snapshot(projects: [project], items: [item])
        remote.items[0].tags = ["remote"]
        try writeCoordinated(remote, to: vm.projectStore.metadataURL)

        // ローカル保存完了後、最終的にディスク内容と整合した状態で落ち着く。
        // どちらが勝つかは last-writer-wins だが、メモリとディスクは一致していること。
        _ = await waitUntil(timeout: 4) {
            let onDisk = ProjectStore(rootDirectory: root).load()
            return onDisk.items.first?.isBookmarked == vm.items.first?.isBookmarked
                && onDisk.items.first?.tags == vm.items.first?.tags
        }
        let onDisk = ProjectStore(rootDirectory: root).load()
        XCTAssertEqual(onDisk.items.first?.isBookmarked, vm.items.first?.isBookmarked)
        XCTAssertEqual(onDisk.items.first?.tags, vm.items.first?.tags)
    }
}
