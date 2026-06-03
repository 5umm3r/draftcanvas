# AGENTS.md - DraftCanvas Development Workflow

## Project

DraftCanvas は macOS 向けの Swift / SwiftUI アプリです。
このリポジトリは Solo モードで運用し、AI エージェントが調査・計画・実装・検証を一貫して担当します。

## Response Rules

- 思考は英語で行い、最終出力は必ず日本語で提供する。
- ユーザーの文末が「！」なら、実装・調査などの行動を開始する。
- ユーザーの文末が「？」なら質問として扱い、明示されない限りコード変更しない。
- ユーザーの文末が「！？」なら、前提確認と深掘りヒアリングを行い、全前提を確認してから計画を提示する。

## Workflow Rules

- 3ステップ以上、または設計判断を含むタスクは、実装前に計画を提示する。
- 途中で行き詰まったら、突き進まず再調査・再計画する。
- 変更は可能な限りシンプルにし、影響範囲を最小限にする。
- 一時しのぎではなく、根本原因を特定して修正する。
- タスク完了前に、可能な範囲でビルド・テスト・ログ・差分確認により動作を証明する。
- 指示なしでコミットしない。
- 指示なしで env ファイルを作成・編集・削除しない。

## Tech Stack

- Swift / SwiftUI（AppKit interop: `NSViewRepresentable` でキャンバスエディタ）
- Rust FFI: `vtracer-ffi/`（SVG ベクタ化用静的ライブラリ）
- SPM は Xcode 内蔵管理。ルートに `Package.swift` はない。
- 外部依存: Sparkle
- バンドルバイナリ: `DraftCanvas/Resources/bin/` に `cwebp`, `oxipng`, `pngquant`, `vtracer`

## Key Structure

- `DraftCanvas/` — アプリ本体（Swift ソース）
- `DraftCanvasTests/` — XCTest ユニットテスト
- `vtracer-ffi/` — Rust 静的ライブラリ。Rust 側変更時のみ `build_universal.sh` で再ビルドする。
- `_docs/` — 内部開発ドキュメント
- `_build/` — ビルド成果物（git 管理外）
- `SPEC.md` — 製品仕様書。機能変更時は必要に応じて更新する。

## Architecture Notes

- MVVM: `DraftCanvasViewModel` は `@MainActor` / `ObservableObject`。
- ViewModel は `ViewModel/DraftCanvasViewModel+*.swift` の extension に分割されている。
- Stores 層: `ProjectStore`, `PromptHistoryStore`, `PromptTemplateStore`, `CanvasThumbnailStore`, `CanvasOriginalImageStore`。
- 非同期生成制御: `GenerationCoordinator`。
- キャンバス編集は AppKit 描画面を SwiftUI でラップする。
- ローカライズは `DraftCanvas/Localization/Localizable.xcstrings` のみを使う。UI 文言は直訳ではなく自然なアプリ文言にする。

## Build

必ず次のコマンドを使う。

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

成果物:

```text
_build/Debug/DraftCanvas.app
```

ビルドルール:

- `SYMROOT` は常に `_build` 固定。
- `OBJROOT` は常に `_build/obj` 固定。
- `-derivedDataPath` は使わない。
- 上記以外の場所にビルド成果物を作った場合は即削除する。

## Test

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj test
```

結果:

```text
_build/TestResults-*.xcresult
```

## Git Rules

- Conventional Commits を使う: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`。
- コミットメッセージは日本語。
- `main` へ直接コミットしない。
- `main` への反映は PR で行う。
- 指示なしで勝手にコミットしない。

## UI / Implementation Rules

- 変更は既存の構造・命名・分割方針に合わせる。
- SwiftUI では既存コンポーネントやローカルなパターンを優先する。
- 絵文字は使わず、必要な場合は SF Symbols などのアイコン・シンボルを使う。
- 「AIっぽい」安易な紫グラデーション中心のデザインは避ける。
- ユーザー向け文言は `xcstrings` に追加し、自然な日本語・英語にする。
