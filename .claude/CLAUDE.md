# CLAUDE.md - DraftCanvas

## 技術スタック

- Swift / SwiftUI（AppKit interop: `NSViewRepresentable` でキャンバスエディタ）
- Rust FFI: `vtracer-ffi/` — SVGベクタ化用静的ライブラリ
- SPM（Xcode内蔵管理、ルートに `Package.swift` なし）
- 外部依存: Sparkle 2.9.1（自動アップデート）
- バンドルバイナリ: `DraftCanvas/Resources/bin/` に cwebp, oxipng, pngquant, vtracer

## ディレクトリ構造

- `DraftCanvas/` — アプリ本体（全Swiftソース）
- `DraftCanvasTests/` — XCTest ユニットテスト
- `vtracer-ffi/` — Rust静的ライブラリ（要別途ビルド: `build_universal.sh`）
- `scripts/` — リリース・リファクタ・バイナリ管理スクリプト
- `_docs/` — 内部開発ドキュメント
- `_build/` — ビルド成果物（git管理外）

## アーキテクチャ

- MVVM: `DraftCanvasViewModel`（`@MainActor`, `ObservableObject`）→ 16個のextensionに分割（`+Generation`, `+Export`, `+Items` 等）
- Stores層: `ProjectStore`, `PromptHistoryStore`, `PromptTemplateStore`, `CanvasThumbnailStore`, `CanvasOriginalImageStore`
- Coordinator: `GenerationCoordinator` — 非同期生成制御
- キャンバス: `CropCanvasNSView`, `SketchCanvasNSView`, `MaskCanvasNSView` — AppKit描画面をSwiftUIでラップ
- ローカライズ: xcstrings形式のみ（`Localizable.xcstrings`）

## キーファイル

- `DraftCanvas/DraftCanvasApp.swift` — エントリポイント（`@main`）
- `DraftCanvas/AppDelegate.swift` — `@NSApplicationDelegateAdaptor`
- `DraftCanvas/ContentView.swift` — ルートビュー（複数extension分割）
- `DraftCanvas/DraftCanvasViewModel.swift` — メインViewModel
- `SPEC.md` — 製品仕様書（50KB）

## ビルド

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

成果物: `_build/Debug/DraftCanvas.app`

ルール:
- SYMROOT は常に `_build`、OBJROOT は常に `_build/obj` 固定
- `-derivedDataPath` は使わない
- 上記以外の場所にビルド成果物を作った場合は即削除する

## テスト

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj test
```

結果: `_build/TestResults-*.xcresult`

## Rust FFI ビルド

`vtracer-ffi/build_universal.sh` で Universal バイナリ生成 → Xcodeプロジェクトにリンク。
Rust側変更時は再ビルド必要。

## Git運用

- Conventional Commits（feat:, fix:, docs:, test:, refactor:, chore:）
- コミットメッセージは日本語
- main への直接コミット禁止
- 指示なしで勝手にコミットしないこと

## 注意事項

- envファイル 勝手に作成・編集・削除しない
- 翻訳は xcstrings 使用、自然な文言にする
- 絵文字不使用、アイコン・シンボル使用
- AIっぽいデザイン禁止（紫グラデーション等）

## サブエージェントのルール

- 調査・探索・並列分析 → サブエージェントへオフロード
- 1エージェント = 1タスク
- Agent tool は既定で `model: "sonnet"` 指定。高度推論が要るときは `model` を省略して親モデルを継承する（モデル名の直書きは世代交代で古くなる）
- 最上位モデルで走らせたい場合はセッション自体を最上位にする。`model` の選択肢は固定の具体名しか受け付けず、「最上位」を指す別名が無いため
- `subagent_type: "fork"` は `model` 指定が無視され、常に親モデルで動く。会話の文脈もそのまま引き継ぐ
- 一調査一報告、解決不能時のみ次の調査を確認
- タスク分割はメインスレッドで処理

## 本番リリース

`main` ブランチで実行:

```bash
git checkout main && git pull origin main
bash scripts/release.sh <version>
```

### リリース時の注意事項

**プロビジョニングプロファイル**
- macOS プロファイルのインストール先は `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`（iOS と異なる）
- ダブルクリックでインストールされない場合は手動コピー
- `scripts/ExportOptions.plist` に `provisioningProfiles` → UUID を明記（`signingStyle: manual` の場合、UUID 未指定だと自動選択されない）
- iCloud capability を entitlements に追加した場合、Developer ID プロファイルを再生成してインストールし直す
- プロファイル再生成時は `scripts/ExportOptions.plist` の `provisioningProfiles` UUID も同時更新する（漏れると export が `No "Developer ID" profiles... matching '<UUID>' are installed` で失敗。UUID確認: `security cms -D -i "<profile>.provisionprofile" | plutil -extract UUID raw -o - -`）

**途中失敗時の再開**
- バージョンバンプ・タグ・push 済みなら `scripts/release.sh` を再実行しない
- アーカイブ済みなら export 以降を手動実行:
  1. `xcodebuild -exportArchive ...`
  2. バイナリ再署名
  3. `xcrun notarytool submit ... --wait`
  4. `xcrun stapler staple`
  5. DMG 作成・署名・公証・staple
  6. `generate_appcast` + `gh release upload`