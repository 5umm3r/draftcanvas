# Codex CLIバージョン表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AccountPopover内にCodex CLIバイナリのバージョン（`codex --version`出力）をアカウント情報の直下に表示する。

**Architecture:** `CodexAppServerClient`に`fetchVersion(executablePath:)`静的メソッドを追加してCLIバージョンを取得。`ImageCreatorViewModel`がアプリ起動時に非同期取得し`@Published var codexVersion`として保持。`AccountPopover`がpropsとして受け取り表示。取得失敗時は`"--"`を表示。

**Tech Stack:** Swift, SwiftUI, Foundation.Process, XCTest

---

## ファイルマップ

| ファイル | 変更種別 | 内容 |
|---------|---------|------|
| `ImageCreator/CodexAppServerClient.swift` | Modify | `static func fetchVersion(executablePath:)` 追加 |
| `ImageCreator/ImageCreatorViewModel.swift` | Modify | `@Published var codexVersion: String = "--"` 追加、`prewarmAndRefresh()`でfetch |
| `ImageCreator/ContentView.swift` | Modify | `AccountPopover`のinitとbodyにバージョン表示追加 |
| `ImageCreatorTests/CodexVersionFetcherTests.swift` | Create | `fetchVersion`のユニットテスト |

---

### Task 1: `fetchVersion` メソッド追加

**Files:**
- Modify: `ImageCreator/CodexAppServerClient.swift`
- Create: `ImageCreatorTests/CodexVersionFetcherTests.swift`

- [ ] **Step 1: テスト作成**

`ImageCreatorTests/CodexVersionFetcherTests.swift` を新規作成:

```swift
import XCTest
@testable import ImageCreator

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

        // "codex" named file → CodexLaunchConfiguration が sibling "node" を使う
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
```

- [ ] **Step 2: テスト失敗確認（実装前）**

```bash
xcodebuild test -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj -only-testing:ImageCreatorTests/CodexVersionFetcherTests 2>&1 | grep -E "error:|FAILED|PASSED"
```

期待: `error: value of type 'CodexAppServerClient' has no member 'fetchVersion'`

- [ ] **Step 3: `fetchVersion` 実装**

`CodexAppServerClient.swift` の `performStart()` の直後（`stop()` の前）に追加:

```swift
    static func fetchVersion(executablePath: String) async -> String? {
        await withCheckedContinuation { continuation in
            let config = CodexLaunchConfiguration.resolve(codexExecutablePath: executablePath)
            // app-server 用の引数末尾2つ（"app-server", "--listen", "stdio://"）を "--version" に置換
            // config.arguments は [codexPath, "app-server", "--listen", "stdio://"] または []
            // "codex" named: [executablePath, "app-server", "--listen", "stdio://"]
            // その他: ["codex", "app-server", "--listen", "stdio://"]
            // いずれも最初の要素（スクリプトパスまたは "codex"）+ "--version" にする
            let versionArgs: [String]
            if let first = config.arguments.first {
                versionArgs = [first, "--version"]
            } else {
                versionArgs = ["--version"]
            }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: config.executablePath)
            process.arguments = versionArgs
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                let trimmed = raw
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                continuation.resume(returning: trimmed?.isEmpty == false ? trimmed : nil)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
```

- [ ] **Step 4: テスト通過確認**

```bash
xcodebuild test -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj -only-testing:ImageCreatorTests/CodexVersionFetcherTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```

期待: `Test Suite 'CodexVersionFetcherTests' passed`

- [ ] **Step 5: コミット**

```bash
git add ImageCreator/CodexAppServerClient.swift ImageCreatorTests/CodexVersionFetcherTests.swift
git commit -m "feat: CodexAppServerClient.fetchVersion でCLIバージョン取得"
```

---

### Task 2: ViewModel に `codexVersion` プロパティ追加

**Files:**
- Modify: `ImageCreator/ImageCreatorViewModel.swift:35-40`（`@Published` プロパティ群）
- Modify: `ImageCreator/ImageCreatorViewModel.swift:338-344`（`prewarmAndRefresh()`）

- [ ] **Step 1: `@Published var codexVersion` 追加**

`ImageCreatorViewModel.swift` の `@Published var isLoggingOut = false` の行（40行目付近）の直後に追加:

```swift
    @Published var codexVersion: String = "--"
```

- [ ] **Step 2: `prewarmAndRefresh()` でバージョン取得**

`prewarmAndRefresh()` メソッド（338行目付近）を以下に更新:

```swift
    private func prewarmAndRefresh() {
        accountUsagePrewarmFailed = false
        Task {
            await refreshAvailableModels()
        }
        Task {
            let version = await CodexAppServerClient.fetchVersion(
                executablePath: client.codexExecutablePath
            )
            self.codexVersion = version ?? "--"
        }
        refreshAccountUsage()
    }
```

- [ ] **Step 3: `codexExecutablePath` をアクセス可能にする**

`CodexAppServerClient.swift` の `private let codexExecutablePath: String` を `internal` に変更:

```swift
    let codexExecutablePath: String
```

（`private` を削除するだけ）

- [ ] **Step 4: ビルド確認**

```bash
xcodebuild -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build 2>&1 | grep -E "error:|warning:|BUILD"
```

期待: `BUILD SUCCEEDED`

- [ ] **Step 5: コミット**

```bash
git add ImageCreator/ImageCreatorViewModel.swift ImageCreator/CodexAppServerClient.swift
git commit -m "feat: 起動時にCodex CLIバージョンをViewModelに保持"
```

---

### Task 3: AccountPopover にバージョン表示追加

**Files:**
- Modify: `ImageCreator/ContentView.swift:1362-1435`（`AccountPopover` struct）
- Modify: `ImageCreator/ContentView.swift:218-235`（`AccountPopover` 呼び出し箇所）

- [ ] **Step 1: `AccountPopover` に `codexVersion` プロパティ追加**

`AccountPopover` struct の定義（1362行目付近）を更新:

```swift
struct AccountPopover: View {
    let status: CodexAccountUsageStatus
    let isLoading: Bool
    let hasFailed: Bool
    let isLoggingOut: Bool
    let codexVersion: String          // ← 追加
    let onRetry: () -> Void
    let onLogout: () -> Void
```

- [ ] **Step 2: ヘッダー下にバージョン表示を追加**

`AccountPopover` の body 内、ヘッダー `HStack` の直後（1410行目付近の `Spacer()` を含む `HStack` 閉じ後）にバージョン行を追加:

```swift
                // ヘッダー
                HStack(spacing: 10) {
                    Image(systemName: status.accountKind.systemImageName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.accountLabel)
                            .font(.headline)
                            .lineLimit(1)
                        if status.planLabel != "-" {
                            Text(status.planLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                }

                // Codex CLIバージョン
                Text("Codex \(codexVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
```

- [ ] **Step 3: `AccountPopover` 呼び出し箇所に `codexVersion` を渡す**

`ContentView.swift` の `.popover` 内の `AccountPopover(...)` 呼び出し（226行目付近）を更新:

```swift
.popover(isPresented: $isAccountPopoverPresented, arrowEdge: .bottom) {
    AccountPopover(
        status: viewModel.accountUsageStatus,
        isLoading: viewModel.isRefreshingAccountUsage,
        hasFailed: viewModel.accountUsagePrewarmFailed,
        isLoggingOut: viewModel.isLoggingOut,
        codexVersion: viewModel.codexVersion,
        onRetry: viewModel.refreshAccountUsage,
        onLogout: viewModel.logout
    )
}
```

- [ ] **Step 4: ビルド確認**

```bash
xcodebuild -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build 2>&1 | grep -E "error:|warning:|BUILD"
```

期待: `BUILD SUCCEEDED`

- [ ] **Step 5: 全テスト確認**

```bash
xcodebuild test -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|error:"
```

期待: `Test Suite 'ImageCreatorTests' passed`

- [ ] **Step 6: コミット**

```bash
git add ImageCreator/ContentView.swift
git commit -m "feat: AccountPopoverにCodex CLIバージョン表示を追加"
```

---

## 完了条件

- [ ] アカウントアイコン → ポップオーバー → ヘッダー下に `"Codex 0.x.x"` 表示
- [ ] Codex CLI未インストール/パス不正時 → `"Codex --"` 表示
- [ ] 全テスト通過
