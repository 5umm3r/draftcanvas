import XCTest
@testable import DraftCanvas

@MainActor
final class BookmarkDeleteProtectionTests: XCTestCase {

    private func makeViewModel() -> DraftCanvasViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftCanvasTests-\(UUID().uuidString)", isDirectory: true)
        return DraftCanvasViewModel(
            projectStore: ProjectStore(rootDirectory: root),
            preferredSaveFolderStore: PreferredSaveFolderStore(
                userDefaults: UserDefaults(suiteName: "DraftCanvasTests-\(UUID().uuidString)")!
            ),
            prewarmOnInit: false
        )
    }

    private func makeItem(
        projectID: UUID,
        prompt: String = "test",
        isBookmarked: Bool = false
    ) -> ProjectItem {
        ProjectItem(
            projectID: projectID,
            prompt: prompt,
            aspectRatio: .square,
            isBookmarked: isBookmarked
        )
    }

    private func addProject(to viewModel: DraftCanvasViewModel) -> UUID {
        let project = Project(name: "テストプロジェクト")
        viewModel.projects.append(project)
        return project.id
    }

    override func tearDown() {
        // @AppStorage 経由の設定はテスト間で汚染されるため必ず戻す。
        UserDefaults.standard.set(false, forKey: "canvasShowsBookmarkedOnly")
        super.tearDown()
    }

    func testDeleteItemDoesNotRemoveBookmarkedItemInNormalView() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        viewModel.canvasShowsBookmarkedOnly = false
        let item = makeItem(projectID: projectID, isBookmarked: true)
        viewModel.items = [item]

        viewModel.deleteItem(item)

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertTrue(viewModel.items.contains { $0.id == item.id })
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testDeleteItemRemovesUnbookmarkedItemInNormalView() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        viewModel.canvasShowsBookmarkedOnly = false
        let item = makeItem(projectID: projectID, isBookmarked: false)
        viewModel.items = [item]

        viewModel.deleteItem(item)

        XCTAssertTrue(viewModel.items.isEmpty)
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testDeleteItemRemovesBookmarkedItemWhenBookmarkedOnlyFilterActive() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        let item = makeItem(projectID: projectID, isBookmarked: true)
        viewModel.items = [item]
        viewModel.canvasShowsBookmarkedOnly = true

        viewModel.deleteItem(item)

        XCTAssertTrue(viewModel.items.isEmpty)
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testDeleteItemsSkipsBookmarkedItemsAndReturnsSkippedCount() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        viewModel.canvasShowsBookmarkedOnly = false
        let bookmarked = makeItem(projectID: projectID, isBookmarked: true)
        let unbookmarked = makeItem(projectID: projectID, isBookmarked: false)
        viewModel.items = [bookmarked, unbookmarked]

        let skipped = viewModel.deleteItems(ids: [bookmarked.id, unbookmarked.id])

        XCTAssertEqual(skipped, 1)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.id, bookmarked.id)
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testDeleteItemsLeavesOnlyProtectedIDsInSelectedItemIDs() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        viewModel.canvasShowsBookmarkedOnly = false
        let bookmarked = makeItem(projectID: projectID, isBookmarked: true)
        let unbookmarked = makeItem(projectID: projectID, isBookmarked: false)
        viewModel.items = [bookmarked, unbookmarked]
        viewModel.selectedItemIDs = [bookmarked.id, unbookmarked.id]

        _ = viewModel.deleteItems(ids: [bookmarked.id, unbookmarked.id])

        XCTAssertEqual(viewModel.selectedItemIDs, [bookmarked.id])
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testBatchDeletePlanReportsDeletableIDsAndProtectedCount() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        viewModel.canvasShowsBookmarkedOnly = false
        let bookmarked = makeItem(projectID: projectID, isBookmarked: true)
        let unbookmarked = makeItem(projectID: projectID, isBookmarked: false)
        viewModel.items = [bookmarked, unbookmarked]

        let plan = viewModel.batchDeletePlan(for: [bookmarked.id, unbookmarked.id])

        XCTAssertEqual(plan.deletableIDs, [unbookmarked.id])
        XCTAssertEqual(plan.protectedCount, 1)
        viewModel.canvasShowsBookmarkedOnly = false
    }

    func testDeleteItemsDeletesAllAndReturnsZeroWhenBookmarkedOnlyFilterActive() {
        let viewModel = makeViewModel()
        let projectID = addProject(to: viewModel)
        let bookmarked = makeItem(projectID: projectID, isBookmarked: true)
        let unbookmarked = makeItem(projectID: projectID, isBookmarked: false)
        viewModel.items = [bookmarked, unbookmarked]
        viewModel.canvasShowsBookmarkedOnly = true

        let skipped = viewModel.deleteItems(ids: [bookmarked.id, unbookmarked.id])

        XCTAssertEqual(skipped, 0)
        XCTAssertTrue(viewModel.items.isEmpty)
        viewModel.canvasShowsBookmarkedOnly = false
    }
}
