# 外部バイナリ管理ワークフロー

対象: `pngquant`・`oxipng`（PNG最適化ツール）
配置先: `ImageCreator/Resources/bin/`

---

## フェーズ1: 初期開発（現在）

バイナリをgitで直接管理。

**セットアップ:**
```bash
# 初回のみ（ビルド済みユニバーサルバイナリが既にリポジトリに含まれる）
git clone ...
xcodebuild -scheme ImageCreator -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

**バイナリ更新時:**
```bash
# x86_64ターゲット追加（初回のみ）
rustup target add x86_64-apple-darwin

# oxipng ビルド
cargo install oxipng --root /tmp/oxipng-arm64 --target aarch64-apple-darwin
cargo install oxipng --root /tmp/oxipng-x86  --target x86_64-apple-darwin
lipo -create /tmp/oxipng-arm64/bin/oxipng /tmp/oxipng-x86/bin/oxipng \
     -output ImageCreator/Resources/bin/oxipng

# pngquant ビルド
git clone --depth 1 https://github.com/kornelski/pngquant.git /tmp/pngquant
cd /tmp/pngquant && git submodule update --init
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create target/aarch64-apple-darwin/release/pngquant \
             target/x86_64-apple-darwin/release/pngquant \
     -output /path/to/repo/ImageCreator/Resources/bin/pngquant

chmod +x ImageCreator/Resources/bin/oxipng ImageCreator/Resources/bin/pngquant
```

**依存関係:** `/usr/lib/` のみ（libz, libiconv, libSystem）→ 追加インストール不要

---

## フェーズ2: 配布前（将来）

GitHub Releases + CI/CDに移行。

**移行手順:**
1. `ImageCreator/Resources/bin/pngquant` と `oxipng` を `.gitignore` に追加
2. バイナリをGitHub Releaseアセットにアップロード
3. `scripts/fetch-tools.sh` 作成
4. GitHub Actions設定（ビルド→署名→Notarize→DMG）

**fetch-tools.sh の概要:**
```bash
#!/bin/bash
set -e
VERSION="v1.0.0"  # リリースタグ
BIN_DIR="ImageCreator/Resources/bin"

gh release download "$VERSION" --pattern "pngquant" --dir "$BIN_DIR"
gh release download "$VERSION" --pattern "oxipng"   --dir "$BIN_DIR"
chmod +x "$BIN_DIR/pngquant" "$BIN_DIR/oxipng"
```

**CI要件（配布時）:**
- Apple Developer ID証明書
- Notarization（`xcrun notarytool`）
- Hardened Runtime（署名スクリプト `--options runtime` 対応済み）

---

## バイナリ仕様

| ツール   | バージョン | アーキテクチャ       | 動的依存     |
|----------|-----------|---------------------|-------------|
| oxipng   | 10.1.1    | arm64 + x86_64 (fat) | /usr/lib/* |
| pngquant | 3.0.4     | arm64 + x86_64 (fat) | /usr/lib/* |
