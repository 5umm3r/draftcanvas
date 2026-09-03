import XCTest
@testable import DraftCanvas

final class ProjectStoreSnapshotTests: XCTestCase {

    func testSnapshotEncodeDecodeRoundtrip() throws {
        let snapshot = ProjectStore.Snapshot()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProjectStore.Snapshot.self, from: data)

        XCTAssertEqual(decoded.projects.count, 0)
        XCTAssertEqual(decoded.sidebarSelection, .none)
    }

    func testLegacyKeyDecoding() throws {
        // selectedProjectID / selectedFilteringProjectID はデコードされても無視される
        // SidebarSelection.none は {"none": true} としてエンコードされる
        let legacyJSON = """
        {
          "projects": [],
          "items": [],
          "filteringProjects": [],
          "sidebarSelection": {"none": true},
          "expandedSections": {},
          "selectedProjectID": "00000000-0000-0000-0000-000000000001",
          "selectedFilteringProjectID": "00000000-0000-0000-0000-000000000002"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(ProjectStore.Snapshot.self, from: legacyJSON)

        XCTAssertEqual(snapshot.projects.count, 0)
        XCTAssertEqual(snapshot.sidebarSelection, .none)
    }

    func testLegacyKeyWithoutSidebarSelection() throws {
        // sidebarSelection キーを持たない旧フォーマット
        // selectedProjectID のみ持つ JSON でデコードすると legacy fallback パスが通り
        // .project(id) になることを確認
        let legacyJSON = """
        {
          "projects": [],
          "items": [],
          "filteringProjects": [],
          "expandedSections": {},
          "selectedProjectID": "00000000-0000-0000-0000-000000000001"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(ProjectStore.Snapshot.self, from: legacyJSON)

        XCTAssertEqual(snapshot.projects.count, 0)
        let expectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertEqual(snapshot.sidebarSelection, .project(expectedID))
    }

    func testLegacyItemWithoutIsBookmarkedDecodesToFalse() throws {
        // isBookmarked キーを持たない旧フォーマットの item は false 扱いになることを確認
        let legacyItemJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "projectID": "00000000-0000-0000-0000-000000000004",
          "prompt": "legacy prompt",
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let item = try decoder.decode(ProjectItem.self, from: legacyItemJSON)

        XCTAssertFalse(item.isBookmarked)
    }

    func testIsBookmarkedRoundtripAndOmittedWhenFalse() throws {
        // isBookmarked = true はエンコード後も key が残り、デコードで再現されることを確認
        let bookmarkedItem = ProjectItem(
            projectID: UUID(),
            prompt: "prompt",
            aspectRatio: .square,
            isBookmarked: true
        )

        let encoder = JSONEncoder()
        let bookmarkedData = try encoder.encode(bookmarkedItem)
        let bookmarkedJSON = String(data: bookmarkedData, encoding: .utf8)!
        XCTAssertTrue(bookmarkedJSON.contains("isBookmarked"))

        let decoder = JSONDecoder()
        let decodedBookmarked = try decoder.decode(ProjectItem.self, from: bookmarkedData)
        XCTAssertTrue(decodedBookmarked.isBookmarked)

        // isBookmarked = false（デフォルト）は key を出力しないことを確認
        let unbookmarkedItem = ProjectItem(
            projectID: UUID(),
            prompt: "prompt",
            aspectRatio: .square
        )
        let unbookmarkedData = try encoder.encode(unbookmarkedItem)
        let unbookmarkedJSON = String(data: unbookmarkedData, encoding: .utf8)!
        XCTAssertFalse(unbookmarkedJSON.contains("isBookmarked"))
    }
}
