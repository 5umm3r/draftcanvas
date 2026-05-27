---
name: tool-changelog-check
description: Use when a CLI tool, package, or SDK has been upgraded to a new version and you need to know what changed between two version numbers and whether the current project is affected by those changes.
---

# Tool Changelog Check

## Overview

ツールのバージョンアップ時に変更内容を調査し、現プロジェクトへの影響を判断する。

## Steps

1. **変更内容調査** — サブエージェントに委譲
   - GitHub releases ページで対象バージョン間の全リリースノートを取得
   - カテゴリ別に整理: 新機能 / バグ修正 / モデル変更 / 破壊的変更
   - `model: "sonnet"` 指定

2. **影響評価** — メインスレッドで判断
   - プロジェクトが対象ツールを依存関係として持つか確認
   - 破壊的変更・API変更が現コードに該当するか確認
   - 「影響なし」の場合はその根拠を明示

## Output Format

```
**[v旧]→[v新] 変更サマリ**

- [0.131.0] 新機能: ...
- [0.132.0] バグ修正: ...
- [0.133.0] 破壊的変更: なし

**このプロジェクトへの影響: なし / あり**
理由: [依存関係なし / 影響箇所: file:line]
```

## Common Mistakes

- モデル変更の有無を見落とす → リリースノートの `models.json` 自動更新コミットも確認
- 「影響なし」を根拠なく断言 → 必ずプロジェクトの依存関係を確認してから判断
