import XCTest
@testable import DraftCanvas

final class CodexVersionFetcherTests: XCTestCase {

    func testFetchVersionReturnsNilForMissingExecutable() async {
        let version = await CodexAppServerClient.fetchVersion(
            executablePath: "/nonexistent/path/codex"
        )
        XCTAssertNil(version)
    }

    func testFetchVersionParsesOutput() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // "codex" named → CodexLaunchConfiguration が sibling "node" を使う
        // node スクリプト: 第2引数が "--version" なら "0.1.2" を出力
        let nodeScript = """
        #!/bin/sh
        if [ "$2" = "--version" ]; then
          echo "0.1.2"
        fi
        """
        let nodePath = tempDir.appendingPathComponent("node").path
        try nodeScript.write(toFile: nodePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: nodePath
        )

        let codexPath = tempDir.appendingPathComponent("codex").path
        try "".write(toFile: codexPath, atomically: true, encoding: .utf8)

        let version = await CodexAppServerClient.fetchVersion(executablePath: codexPath)
        XCTAssertEqual(version, "0.1.2")
    }

    func testFetchVersionTrimsWhitespace() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nodeScript = """
        #!/bin/sh
        if [ "$2" = "--version" ]; then
          printf "  0.2.0\\n"
        fi
        """
        let nodePath = tempDir.appendingPathComponent("node").path
        try nodeScript.write(toFile: nodePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: nodePath
        )

        let codexPath = tempDir.appendingPathComponent("codex").path
        try "".write(toFile: codexPath, atomically: true, encoding: .utf8)

        let version = await CodexAppServerClient.fetchVersion(executablePath: codexPath)
        XCTAssertEqual(version, "0.2.0")
    }
}
