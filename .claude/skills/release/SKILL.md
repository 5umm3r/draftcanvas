---
name: release
description: DraftCanvas を本番リリースする一連の手順。CHANGELOG に次期バージョンを追記し、dev でコミット・プッシュ、main へ PR 作成・マージ、main で scripts/release.sh を実行して署名・公証・DMG 作成・appcast 生成・GitHub Release まで通す。「リリースして」「1.2.19 を出して」「本番に出して」「配信して」「PR 作ってマージしてリリース」と言われたときに使う。機能実装が終わって「これを出したい」「バージョン上げて」と言われたとき、リリース前の前提確認だけを頼まれたとき、release.sh が途中で失敗して再開したいときにも必ず使う。
---

# DraftCanvas リリース

Sparkle による自動更新配信を含む本番リリース。実行すると全ユーザーにアップデートが届くため、
やり直しが利かない工程（タグ push、GitHub Release、appcast 配信）が含まれる。
`scripts/release.sh` は途中で失敗してもタグと push は済んでしまうので、
**走らせる前に落ちる条件を潰しておく**のがこのスキルの主眼。

## 全体像

```
dev ブランチ                          main ブランチ
─────────────────────────────────────────────────────
1. CHANGELOG 追記
2. コミット・プッシュ
3. PR 作成 ──────────────────────▶ 4. マージ
                                     5. pull（ff）
                                     6. preflight チェック
                                     7. release.sh 実行
```

バージョン番号は `scripts/release.sh` が自分でバンプしてタグを打つ。
Info.plist や pbxproj を手で書き換える必要はない。

---

## Step 1: CHANGELOG に次期バージョンを追記

`CHANGELOG.md` の先頭（`# Changelog` の直後）に新セクションを足す。

```markdown
## [1.2.19] - 2026-07-30

### 追加

- 機能の説明。何ができるようになったかを利用者目線で書く

### 変更

- 既存挙動が変わった点。変えた理由も一緒に書く
```

見出しの形式は必ず `## [<version>] - <YYYY-MM-DD>` にする。`release.sh` はこの見出しを
sed で拾って appcast の `<description>` に流し込むため、形式がずれるとアップデート通知の
リリースノートが空欄で配信される。日付はリリース実行日。

セクション見出しは既存の慣習に合わせて `### 追加` / `### 変更` / `### 修正` / `### 改善` を使う。

**箇条書きはネストさせない。** `release.sh` の HTML 変換は `s|^- \(.*\)|<li>\1</li>|` で
行頭の `- ` だけを `<li>` にするため、インデントした `  - ` は変換されずに生のハイフンのまま
appcast に混入し、アップデート通知に `- 項目名` がそのまま表示される。
詳細を並べたいときは 1 項目にまとめるか、フラットな箇条書きとして並べる。

同じ理由で、**インライン記法も avoid する**。変換されるのは `### 見出し` と `- 箇条書き` だけなので、
バッククォートや `**強調**` はそのままの文字として通知に表示される。CHANGELOG 側の可読性より
配信される見た目を優先し、コード片は記号なしで書く。

```markdown
# 崩れる
- ズーム表示を追加
  - コントロールバーに倍率インジケータ
  - `⌘+` / `⌘-` のショートカット

# 崩れない
- ズーム表示を追加。コントロールバーに倍率インジケータ、⌘+ / ⌘- のショートカットを備える
- ピクセル表示トグルを追加。拡大時に nearest neighbor 描画へ切り替える
```

現在のバージョンは `git tag --sort=-v:refname | head -1` か CHANGELOG の先頭で確認する。

## Step 2: dev でコミット・プッシュ

作業は `dev` ブランチで行う（main への直接コミットは禁止）。

```bash
git add -A
git commit -F - <<'EOF'
feat: 変更内容の要約

本文。何を変えたかではなく、なぜそうしたかを書く。
挙動が変わる場合はその影響も明記する。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git push origin dev
```

Conventional Commits（feat: / fix: / docs: / test: / refactor: / chore:）で、
メッセージ本体は日本語。

**新規 Swift ファイルを追加した場合**は、コミット前に Xcode プロジェクトへの登録を確認する。
このプロジェクトは `fileSystemSynchronizedGroups` を使っていないため、ファイルを置くだけでは
ビルド対象にならない。`project.pbxproj` の 4 箇所に手で追記する必要がある。

```bash
# 登録漏れの検出（ビルドは通るのに実行時に落ちる、という事態を防ぐ）
for f in $(git diff --name-only --diff-filter=A HEAD~1 | grep '\.swift$'); do
  base=$(basename "$f")
  grep -q "$base" DraftCanvas.xcodeproj/project.pbxproj \
    && echo "[OK] $base" || echo "[NG] $base が pbxproj に未登録"
done
```

追記する 4 箇所は、既存ファイル（例: `ExpandedImageSheet.swift`）の行を検索して真似るのが確実。
`PBXBuildFile` / `PBXFileReference` / グループの `children` / `PBXSourcesBuildPhase` の `files`。
ID は既存と衝突しない 32 桁の 16 進文字列を使う。

## Step 3: main へ PR を作成してマージ

```bash
gh pr create --base main --head dev --title "<コミットと同じ要約>" --body "$(cat <<'EOF'
## 概要

## 実装

## 挙動変更

## 確認

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr merge <PR番号> --merge
```

`gh pr merge` はコマンドが成功しても出力を返さないことがある。マージされたかは必ず確認する。

```bash
gh pr view <PR番号> --json state,mergeCommit --jq '{state, oid: .mergeCommit.oid}'
```

## Step 4: main に切り替えて同期

```bash
git checkout main
git fetch origin
git merge --ff-only origin/main
```

同期できたかは `git log` の表示ではなく SHA で確認する。

```bash
echo "HEAD=$(git rev-parse HEAD)"
echo "origin/main=$(git rev-parse origin/main)"
```

この 2 つが一致していれば OK。マージコミットが作られているので、
ローカルの HEAD が PR のコミット（マージ前）のままになっていないか注意する。

## Step 5: 前提条件チェック

`release.sh` が途中で落ちる条件を先に洗い出す。

```bash
bash .claude/skills/release/scripts/preflight.sh <version>
```

チェック内容: ブランチと作業ツリーの状態、origin/main との同期、タグの重複、
CHANGELOG の見出しと本文、Sparkle の EdDSA 秘密鍵と `generate_appcast`、
公証の keychain profile `DC_NOTARY`、プロビジョニングプロファイルの UUID 一致、
Developer ID 証明書、`gh` の認証。

**プロファイルの UUID チェックが特に重要**。`scripts/ExportOptions.plist` は
`signingStyle: manual` なので、UUID が一致するプロファイルがインストールされていないと
export が `No "Developer ID" profiles ... matching '<UUID>'` で落ちる。
インストール済みプロファイルのファイル名は UUID とは限らない（`DraftCanvas_Developer_ID.provisionprofile`
のような名前でも中身の UUID が一致していれば有効）ため、ファイル名ではなく中身で照合する。
preflight はこれを中身で見ている。

NG が出たら解消してから次へ進む。ここで止まる方が、タグを打った後で失敗するより遥かに安い。

## Step 6: リリース実行

```bash
bash scripts/release.sh <version> 2>&1 | tee <scratchpad>/release-<version>.log
```

アーカイブ（Release ビルド）と公証 2 回（app と DMG）で 10〜20 分かかるため、
バックグラウンドで走らせてログを追う。進捗はフェーズ見出しで確認できる。

```bash
grep -E "^==> |^Error|status: " <ログパス> | tail -12
```

`release.sh` が順に行うこと:

1. バージョンバンプ（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）→ コミット → タグ → push
2. Release アーカイブ → export
3. Sparkle の不要ローカライズ削除
4. 同梱バイナリと app の再署名（Hardened Runtime）
5. app の公証 + staple
6. DMG 作成 → 署名 → 公証 + staple
7. appcast 生成 + EdDSA 署名 + CHANGELOG からリリースノート注入
8. GitHub Release 作成とアセットアップロード

完了後の確認:

```bash
spctl -a -vvv -t install _build/DraftCanvas.dmg
gh release view v<version> --repo 5umm3r/draftcanvas --json assets --jq '[.assets[].name]'
```

`appcast.xml` と `DraftCanvas.dmg` の 2 つが上がっていればリリース完了。

---

## 途中で失敗したときの再開

**`release.sh` を頭から再実行してはいけない。** バージョンバンプ・タグ・push が済んでいると
「タグが既に存在する」で落ちるか、二重にコミットが積まれる。どこまで進んだかをログの
`==>` 見出しで特定し、その先を手で実行する。

```bash
VERSION=1.2.19
BUILD=$(git rev-list --count HEAD)
ARCHIVE=_build/DraftCanvas.xcarchive
EXPORT_DIR=_build/Export
DMG_PATH=_build/DraftCanvas.dmg
```

- **Archive で失敗** → 原因を直してコミットし直す。タグは打ち直しになるので
  `git tag -d v$VERSION && git push origin :refs/tags/v$VERSION` でタグを消してから再実行
- **Export 以降で失敗** → アーカイブは再利用できる。`scripts/release.sh` の該当行から手で流す:
  1. `xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" -exportOptionsPlist scripts/ExportOptions.plist`
  2. `Contents/Resources/bin/` 配下と app 本体を Developer ID で再署名
  3. `xcrun notarytool submit ... --keychain-profile DC_NOTARY --wait` → `xcrun stapler staple`
  4. DMG 作成・署名・公証・staple
  5. `generate_appcast` → `gh release upload v$VERSION ... --clobber`
- **公証が Invalid** → `xcrun notarytool log <submission-id> --keychain-profile DC_NOTARY` で
  詳細を読む。署名漏れの同梱バイナリが原因なことが多い

プロファイルを再生成した場合は、`scripts/ExportOptions.plist` の
`provisioningProfiles` の UUID も必ず同時に更新する。片方だけ直すと export で落ちる。

```bash
security cms -D -i "<profile>.provisionprofile" | plutil -extract UUID raw -o - -
```

---

## 注意

- リリースは外部公開かつ不可逆。Sparkle 経由で全ユーザーに自動更新が届く。
  ユーザーから明示的な指示がない限り実行しない
- `_build/` 以外の場所にビルド成果物を作らない
- 途中経過は逐一報告する。特に「タグを push した」時点は後戻りのコストが変わる境界なので、
  そこを越えたかどうかは明確に伝える
