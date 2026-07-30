#!/usr/bin/env bash
# DraftCanvas リリース前の前提条件チェック。
# release.sh は途中まで進んでから失敗すると再開が面倒（タグと push が済んでしまう）ため、
# 走らせる前に落ちる条件を洗い出す。
#
# Usage: bash .claude/skills/release/scripts/preflight.sh <version>
# 例:    bash .claude/skills/release/scripts/preflight.sh 1.2.19

set -uo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> (e.g. 1.2.19)" >&2
  exit 2
fi

FAILURES=0
ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
ng()   { printf '  [NG]   %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

echo "==> リリース前チェック: v${VERSION}"

# --- 1. Git の状態 -----------------------------------------------------------
echo "[1/7] Git"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ]; then
  ok "ブランチ: main"
else
  ng "ブランチが main ではない (現在: ${BRANCH})。release.sh は main で実行する"
fi

if git diff --quiet && git diff --cached --quiet; then
  ok "作業ツリーは clean"
else
  ng "uncommitted 変更あり。release.sh は冒頭でこれを検出して中断する"
fi

git fetch origin --quiet 2>/dev/null || true
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "")
if [ -n "$REMOTE" ] && [ "$LOCAL" = "$REMOTE" ]; then
  ok "origin/main と同期済み"
elif [ -n "$REMOTE" ]; then
  ng "ローカル main が origin/main と不一致。git merge --ff-only origin/main を先に実行する"
else
  warn "origin/main を解決できなかった"
fi

if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  ng "タグ v${VERSION} が既に存在する。バージョンを上げるか、既存タグを確認する"
else
  ok "タグ v${VERSION} は未使用"
fi

# --- 2. CHANGELOG ------------------------------------------------------------
# release.sh は sed で "## [VERSION]" 見出しから次の "## [" までを抜き出し、
# appcast の <description> に流し込む。見出しが無いとリリースノートが空で配信される。
echo "[2/7] CHANGELOG"
if grep -q "^## \[${VERSION}\]" CHANGELOG.md 2>/dev/null; then
  NOTES=$(sed -n "/^## \[${VERSION}\]/,/^## \[/{/^## \[${VERSION}\]/d;/^## \[/d;p;}" CHANGELOG.md)
  if [ -n "$(echo "$NOTES" | tr -d '[:space:]')" ]; then
    ok "## [${VERSION}] の見出しと本文あり（$(echo "$NOTES" | grep -c '^- ') 項目）"
    # release.sh の HTML 変換は行頭の "- " しか <li> にしないため、
    # インデントした箇条書きは生のハイフンのまま appcast に混入する
    NESTED=$(echo "$NOTES" | grep -c '^[[:space:]]\+- ')
    if [ "$NESTED" -gt 0 ]; then
      warn "ネストした箇条書きが ${NESTED} 行ある。appcast のリリースノートに生の '- ' が残る（フラットな箇条書きに直すと崩れない）"
    else
      ok "箇条書きはすべてトップレベル"
    fi
  else
    ng "## [${VERSION}] の見出しはあるが本文が空。appcast のリリースノートが空になる"
  fi
else
  ng "CHANGELOG.md に '## [${VERSION}]' の見出しが無い。この形式でないと release.sh が抽出できない"
fi

# --- 3. Sparkle 署名鍵 -------------------------------------------------------
echo "[3/7] Sparkle"
SPARKLE_KEY_FILE="${HOME}/.config/sparkle/ed_private_key"
if [ -f "$SPARKLE_KEY_FILE" ]; then
  ok "EdDSA 秘密鍵: ${SPARKLE_KEY_FILE}"
else
  ng "EdDSA 秘密鍵が無い: ${SPARKLE_KEY_FILE}"
fi

GENERATE_APPCAST="$(command -v generate_appcast 2>/dev/null \
  || find /usr/local/Caskroom/sparkle /opt/homebrew/Caskroom/sparkle -name generate_appcast -not -path '*dSYM*' 2>/dev/null | sort -r | head -1 \
  || true)"
if [ -n "$GENERATE_APPCAST" ]; then
  ok "generate_appcast: ${GENERATE_APPCAST}"
else
  ng "generate_appcast が見つからない。brew install --cask sparkle"
fi

# --- 4. 公証プロファイル -----------------------------------------------------
echo "[4/7] 公証 (notarytool)"
if xcrun notarytool history --keychain-profile DC_NOTARY >/dev/null 2>&1; then
  ok "keychain profile 'DC_NOTARY' で認証できる"
else
  ng "keychain profile 'DC_NOTARY' が使えない。xcrun notarytool store-credentials DC_NOTARY で再登録する"
fi

# --- 5. プロビジョニングプロファイル ------------------------------------------
# ExportOptions.plist は signingStyle=manual なので、UUID が一致するプロファイルが
# インストールされていないと export が "No Developer ID profiles ... matching" で落ちる。
# ファイル名が UUID とは限らないため、中身の UUID で照合する。
echo "[5/7] プロビジョニングプロファイル"
EXPECTED_UUID=$(plutil -extract provisioningProfiles.com\\.spade3\\.DraftCanvas raw -o - scripts/ExportOptions.plist 2>/dev/null || echo "")
if [ -z "$EXPECTED_UUID" ]; then
  ng "scripts/ExportOptions.plist から provisioningProfiles の UUID を読めない"
else
  PROFILE_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
  MATCHED=""
  MATCHED_EXPIRY=""
  if [ -d "$PROFILE_DIR" ]; then
    for f in "$PROFILE_DIR"/*.provisionprofile; do
      [ -f "$f" ] || continue
      DECODED=$(security cms -D -i "$f" 2>/dev/null) || continue
      UUID=$(echo "$DECODED" | plutil -extract UUID raw -o - - 2>/dev/null) || continue
      if [ "$UUID" = "$EXPECTED_UUID" ]; then
        MATCHED="$f"
        MATCHED_EXPIRY=$(echo "$DECODED" | plutil -extract ExpirationDate raw -o - - 2>/dev/null || echo "?")
        break
      fi
    done
  fi
  if [ -n "$MATCHED" ]; then
    ok "UUID ${EXPECTED_UUID} → $(basename "$MATCHED") (期限: ${MATCHED_EXPIRY})"
  else
    ng "UUID ${EXPECTED_UUID} のプロファイルが未インストール。再生成して ${PROFILE_DIR}/ に配置し、ExportOptions.plist の UUID も更新する"
  fi
fi

# --- 6. 署名証明書 -----------------------------------------------------------
echo "[6/7] 署名証明書"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  ok "Developer ID Application 証明書あり"
else
  ng "Developer ID Application 証明書が見つからない"
fi

# --- 7. GitHub CLI -----------------------------------------------------------
echo "[7/7] GitHub"
if gh auth status >/dev/null 2>&1; then
  ok "gh 認証済み"
else
  ng "gh が未認証。gh auth login を実行する"
fi

if gh release view "v${VERSION}" --repo 5umm3r/draftcanvas >/dev/null 2>&1; then
  warn "GitHub Release v${VERSION} が既に存在する（release.sh は --clobber で上書きする）"
else
  ok "GitHub Release v${VERSION} は未作成"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "==> すべて通過。bash scripts/release.sh ${VERSION} を実行できる"
  exit 0
else
  echo "==> ${FAILURES} 件の問題あり。解消してから release.sh を実行する" >&2
  exit 1
fi
