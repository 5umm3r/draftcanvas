# リリース手順

## 概要

`./scripts/release.sh <version>` 一発で以下をすべて自動実行:

1. Xcode Release ビルド (archive)
2. Developer ID 署名 + Hardened Runtime
3. Apple 公証 (notarize × 2)
4. DMG 作成・署名・公証
5. appcast.xml 生成 (EdDSA 署名付き)
6. GitHub Releases へアップロード

ビルド番号は `git rev-list --count HEAD` で自動算出。どの Mac からリリースしても同一 main ブランチなら同じ番号になる。

---

## 初回セットアップ（Mac ごとに 1 回）

### 1. Xcode / 証明書

- Xcode インストール済みであること
- **Developer ID Application** 証明書が Keychain に登録済みであること
  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```

### 2. notarytool プロファイル

Apple ID + App-specific password で `DC_NOTARY` プロファイルを登録:

```bash
xcrun notarytool store-credentials DC_NOTARY \
  --apple-id "your@apple.com" \
  --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

確認:
```bash
xcrun notarytool history --keychain-profile DC_NOTARY
```

### 3. Sparkle CLI

```bash
brew install --cask sparkle
```

quarantine 解除は release.sh が自動実行するため手動不要。

### 4. Sparkle EdDSA 秘密鍵

秘密鍵を `~/.config/sparkle/ed_private_key` に保存 (base64 文字列、改行なし):

```bash
mkdir -p ~/.config/sparkle
printf 'YOUR_BASE64_PRIVATE_KEY_HERE' > ~/.config/sparkle/ed_private_key
chmod 600 ~/.config/sparkle/ed_private_key
```

**別 Mac から移植する場合:**
```bash
# 既存 Mac で秘密鍵を取り出す
security find-generic-password -s "Sparkle EdDSA Private Key" -w
# → 出力された base64 文字列を新 Mac の上記ファイルに保存
```

> 秘密鍵に対応する公開鍵は xcodeproj の `SUPublicEDKey` に設定済み。
> キーペアを変更した場合は xcodeproj を更新して再ビルドが必要。

### 5. GitHub CLI

```bash
brew install gh
gh auth login
```

リリース先リポジトリ: `5umm3r/draftcanvas-releases`

---

## リリース実行

```bash
./scripts/release.sh 1.0.0
```

バージョン番号だけ変えれば次回以降も同じコマンド:

```bash
./scripts/release.sh 1.1.0
./scripts/release.sh 1.2.0
```

所要時間: **20〜30 分**（公証の待ち時間次第）

### 実行前チェック

- uncommitted 変更がないこと（あれば自動で中断）
- main ブランチにいること（ビルド番号 = main の commit 数と一致させるため）

---

## 生成アセット

- `_build/DraftCanvas.dmg` — 配布用 DMG（公証・ステープル済）
- `_build/appcast/appcast.xml` — Sparkle 更新フィード（EdDSA 署名済）

GitHub Releases への自動アップロード後、Sparkle feedURL:
`https://github.com/5umm3r/draftcanvas-releases/releases/latest/download/appcast.xml`
が即座に有効になる。

---

## 検証

```bash
# DMG 署名・公証確認
spctl -a -vvv -t install "_build/DraftCanvas.dmg"

# appcast.xml の内容確認
cat _build/appcast/appcast.xml
```

appcast.xml に含まれるべき要素:
- `sparkle:version` = ビルド番号（git commit 数）
- `sparkle:shortVersionString` = マーケティングバージョン（例: `1.0.0`）
- `sparkle:edSignature` = EdDSA 署名
- `url` = `https://github.com/5umm3r/draftcanvas-releases/releases/latest/download/DraftCanvas.dmg`

---

## トラブルシューティング

**`generate_appcast not found`**
```bash
brew install --cask sparkle
```

**`Error: Sparkle private key not found`**
→ `~/.config/sparkle/ed_private_key` が存在しない。セットアップ手順 4 を実施。

**`uncommitted changes detected`**
→ コミットまたは `git stash` してから再実行。

**公証タイムアウト**
→ Apple サーバーの混雑。再実行で通ることがほとんど。

**`DC_NOTARY` プロファイルエラー**
→ セットアップ手順 2 を再実施（App-specific password の有効期限切れの場合あり）。
