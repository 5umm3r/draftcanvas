# AGENTS.md - DraftCanvas Development Workflow

## Project Overview

**Project**: DraftCanvas

---

## Mode: Solo

このプロジェクトは **Solo モード** で運用します。
AIエージェントが計画・実装・レビューを一貫して担当します。

---

## Codex Imported Guidance

### Response Rules
- 思考は英語で行い、最終出力は必ず日本語で提供する
- ユーザーの文末が「！」なら実装・調査などの行動を開始する
- ユーザーの文末が「？」なら質問として扱い、明示されない限りコード変更しない

### Workflow Rules
- 3ステップ以上または設計判断を含むタスクは、実装前に計画を提示する
- 途中で行き詰まったら、突き進まず再計画する
- タスク完了前に可能な範囲でテスト・ログ・差分確認により動作を証明する
- 指示なしでコミットしない
- 指示なしで env ファイルを作成・編集・削除しない

### Git Rules
- コンベンショナルコミット（`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`）を使う
- コミットメッセージは日本語
- main へ直接コミットしない
- PR で main にマージする

### Implementation Rules
- 変更は可能な限りシンプルにし、影響範囲を最小限にする
- 一時しのぎではなく根本原因を特定して修正する
- 翻訳は直訳ではなく、アプリUIとして自然な文言にする

### ビルド
- ビルドした成果物は _build/ ディレクトリに格納