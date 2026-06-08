**日本語** | [English](CONTRIBUTING.md)

# Contributing

Draft Canvas への貢献ありがとうございます。

## Issue

バグ報告や機能提案は [Issues](https://github.com/5umm3r/draftcanvas/issues) へ。

- バグ: 再現手順、macOS バージョン、ログ (ログウィンドウからコピー可) を添付
- 機能提案: ユースケースと期待する動作を記載

## Pull Request

1. `dev` から feature ブランチを作成
2. [Conventional Commits](https://www.conventionalcommits.org/) 形式でコミット (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
3. コミットメッセージは日本語
4. テスト追加・既存テスト通過を確認
5. PR を作成

## ビルド

```bash
# アプリビルド
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj build

# テスト
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj test

# Rust FFI (vtracer-ffi/ 変更時のみ)
cd vtracer-ffi && ./build_universal.sh
```

## コーディング規約

- Swift / SwiftUI、MVVM パターン
- アイコンは SF Symbols を使用
- 絵文字不使用
- ローカライズは xcstrings 形式
