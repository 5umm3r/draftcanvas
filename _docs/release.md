# リリース手順

## 前提ツール

- **Xcode**: Developer ID Application 証明書、`DC_NOTARY` notarytool プロファイル設定済
- **Sparkle CLI**: `generate_appcast` コマンドが PATH に存在すること
  ```bash
  brew install --cask sparkle
  which generate_appcast  # /opt/homebrew/bin/generate_appcast 等
  ```
- **Sparkle EdDSA 秘密鍵**: `generate_appcast` が keychain から自動読込。xcodeproj の `SUPublicEDKey` と対になるキーが登録済であること
  - 確認: `sparkle_generate_keys -e`（既存キー確認）

## 実行

```bash
./scripts/release.sh 1.0.0
```

- uncommitted 変更があれば中断 → `git commit` または `git stash` 後に再実行
- ビルド番号は `git rev-list --count HEAD` で自動算出（どのデバイスでも同一 main ブランチ = 同じ番号）

## 生成アセット

- `_build/DraftCanvas.dmg` — 配布用 DMG（公証・ステープル済）
- `_build/appcast/appcast.xml` — Sparkle 更新フィード（EdDSA 署名済）

## GitHub Releases へのアップロード

1. `5umm3r/draftcanvas-releases` リポジトリで新規 Release 作成（タグ: `v1.0.0`）
2. Assets にアップロード:
   - `_build/DraftCanvas.dmg`
   - `_build/appcast/appcast.xml`
3. Release を **latest** に設定（Sparkle feedURL が `.../releases/latest/download/appcast.xml` のため）

## 検証

```bash
# DMG 署名確認
spctl -a -vvv -t install "_build/DraftCanvas.dmg"

# appcast.xml の内容確認（バージョン・署名属性が揃っているか）
cat _build/appcast/appcast.xml
```

appcast.xml に含まれるべき属性:
- `sparkle:version` = ビルド番号（git commit 数）
- `sparkle:shortVersionString` = マーケティングバージョン（例: `1.0.0`）
- `sparkle:edSignature` = EdDSA 署名
- `length` = DMG ファイルサイズ（バイト）
