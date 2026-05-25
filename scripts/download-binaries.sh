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
# GitHub に macOS 事前ビルドバイナリなし → Homebrew のバイナリを収集して Universal 化
echo ""
echo "==> pngquant: Homebrew バイナリを収集中..."

ARM_PQ="/opt/homebrew/bin/pngquant"
X86_PQ="/usr/local/bin/pngquant"

HAS_ARM=false; HAS_X86=false
[ -f "$ARM_PQ" ] && HAS_ARM=true
[ -f "$X86_PQ" ] && HAS_X86=true

if $HAS_ARM && $HAS_X86; then
  lipo -create "$ARM_PQ" "$X86_PQ" -output "$BIN_DIR/pngquant"
  echo "  Universal Binary 作成完了"
elif $HAS_ARM; then
  cp "$ARM_PQ" "$BIN_DIR/pngquant"
  echo "  WARNING: arm64 のみ (x86_64 未検出)"
elif $HAS_X86; then
  cp "$X86_PQ" "$BIN_DIR/pngquant"
  echo "  WARNING: x86_64 のみ (arm64 未検出 — Rosetta 経由で動作)"
else
  echo "  ERROR: pngquant が見つかりません。"
  echo "  インストール: brew install pngquant"
  exit 1
fi

chmod +x "$BIN_DIR/pngquant"
echo "  ok: $BIN_DIR/pngquant"
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
