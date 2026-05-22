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
}
