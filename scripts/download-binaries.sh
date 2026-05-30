#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/DraftCanvas/Resources/bin"
mkdir -p "$BIN_DIR"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ── oxipng ────────────────────────────────────────────────────────────────────
OXI_VERSION="9.1.5"
echo "==> oxipng v${OXI_VERSION} ダウンロード中..."

curl -sSL -o "$TMP/arm.tar.gz" \
  "https://github.com/shssoichiro/oxipng/releases/download/v${OXI_VERSION}/oxipng-${OXI_VERSION}-aarch64-apple-darwin.tar.gz"
curl -sSL -o "$TMP/x86.tar.gz" \
  "https://github.com/shssoichiro/oxipng/releases/download/v${OXI_VERSION}/oxipng-${OXI_VERSION}-x86_64-apple-darwin.tar.gz"

tar -xzf "$TMP/arm.tar.gz" -C "$TMP"
mv "$TMP/oxipng-${OXI_VERSION}-aarch64-apple-darwin/oxipng" "$TMP/oxi-arm"

tar -xzf "$TMP/x86.tar.gz" -C "$TMP"
mv "$TMP/oxipng-${OXI_VERSION}-x86_64-apple-darwin/oxipng" "$TMP/oxi-x86"

lipo -create "$TMP/oxi-arm" "$TMP/oxi-x86" -output "$BIN_DIR/oxipng"
chmod +x "$BIN_DIR/oxipng"
file "$BIN_DIR/oxipng" | grep -q "universal binary" \
  || { echo "ERROR: oxipng Universal Binary 化失敗"; exit 1; }
echo "  ok: $BIN_DIR/oxipng"
file "$BIN_DIR/oxipng"

# ── pngquant ──────────────────────────────────────────────────────────────────
# pngquant 3.x は純 Rust 実装 (imagequant)。cargo install で両アーキを
# ビルドして lipo で Universal 化する。
# Homebrew bottle は lcms2 等を動的リンクし、Homebrew 非導入のエンドユーザー
# 環境では dyld エラーになる (自己完結でない)。よって brew は使わない。
PQ_VERSION="3.0.3"
echo ""
echo "==> pngquant v${PQ_VERSION}: cargo で Universal Binary をビルド中..."

command -v cargo >/dev/null 2>&1 \
  || { echo "ERROR: cargo が必要です。導入: https://rustup.rs"; exit 1; }
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null 2>&1 || true

# 静的リンク強制で自己完結バイナリ (システム dylib のみ) を生成する:
#   - pkg-config の探索パスを無効化 → libpng/lcms2 を vendored static でビルド
#   - LCMS2_STATIC=1  → lcms2-sys を静的リンク
#   - PNG_STATIC=1    → libpng-sys を vendored static ビルド (build.rs 準拠)
# これを怠ると Homebrew の liblcms2/libpng16 dylib を動的リンクし、
# Homebrew 非導入のエンドユーザー環境で dyld エラーになる。
PQ_ENV=(env PKG_CONFIG_PATH="" PKG_CONFIG_LIBDIR="/nonexistent" LCMS2_STATIC=1 PNG_STATIC=1)

"${PQ_ENV[@]}" cargo install pngquant --version "$PQ_VERSION" \
  --target aarch64-apple-darwin --root "$TMP/pq-arm" --force
"${PQ_ENV[@]}" cargo install pngquant --version "$PQ_VERSION" \
  --target x86_64-apple-darwin  --root "$TMP/pq-x86" --force

PQ_ARM="$TMP/pq-arm/bin/pngquant"
PQ_X86="$TMP/pq-x86/bin/pngquant"
[ -f "$PQ_ARM" ] && [ -f "$PQ_X86" ] \
  || { echo "ERROR: pngquant 両アーキのビルドに失敗"; exit 1; }

lipo -create "$PQ_ARM" "$PQ_X86" -output "$BIN_DIR/pngquant"
chmod +x "$BIN_DIR/pngquant"
file "$BIN_DIR/pngquant" | grep -q "universal binary" \
  || { echo "ERROR: pngquant Universal Binary 化失敗"; exit 1; }

# 自己完結チェック: /usr/lib・/System 以外の dylib に依存していないこと
NONSYS=$(otool -L "$BIN_DIR/pngquant" | tail -n +2 | awk '{print $1}' \
  | grep -vE '^/usr/lib/|^/System/' || true)
if [ -n "$NONSYS" ]; then
  echo "  ERROR: pngquant が非システム dylib に依存 (自己完結でない):"
  echo "$NONSYS"
  exit 1
fi
echo "  ok: $BIN_DIR/pngquant (自己完結)"
file "$BIN_DIR/pngquant"

# ── cwebp ─────────────────────────────────────────────────────────────────────
CWEBP_VERSION="1.5.0"
echo ""
echo "==> cwebp v${CWEBP_VERSION} ダウンロード中..."

curl -sSL -o "$TMP/libwebp-arm.tar.gz" \
  "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${CWEBP_VERSION}-mac-arm64.tar.gz"
curl -sSL -o "$TMP/libwebp-x86.tar.gz" \
  "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${CWEBP_VERSION}-mac-x86-64.tar.gz"

tar -xzf "$TMP/libwebp-arm.tar.gz" -C "$TMP"
tar -xzf "$TMP/libwebp-x86.tar.gz" -C "$TMP"

lipo -create \
  "$TMP/libwebp-${CWEBP_VERSION}-mac-arm64/bin/cwebp" \
  "$TMP/libwebp-${CWEBP_VERSION}-mac-x86-64/bin/cwebp" \
  -output "$BIN_DIR/cwebp"
chmod +x "$BIN_DIR/cwebp"
file "$BIN_DIR/cwebp" | grep -q "universal binary" \
  || { echo "ERROR: cwebp Universal Binary 化失敗"; exit 1; }
echo "  ok: $BIN_DIR/cwebp"
file "$BIN_DIR/cwebp"

# ── LICENSES ──────────────────────────────────────────────────────────────────
cat > "$BIN_DIR/LICENSES.txt" <<EOF
oxipng v${OXI_VERSION} - MIT License
https://github.com/shssoichiro/oxipng

pngquant - GPL v3 (binary only, subprocess invocation — no linking)
https://pngquant.org/

cwebp v${CWEBP_VERSION} - BSD 3-Clause License
https://chromium.googlesource.com/webm/libwebp/
EOF

touch "$BIN_DIR/.gitkeep"
echo ""
echo "==> 完了: $BIN_DIR"
