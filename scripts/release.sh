#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> (e.g. 1.0.0)" >&2
  exit 1
fi

# uncommitted 変更があるとビルド番号とコミット数が一致しないため中断
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: uncommitted changes detected. Commit or stash before releasing." >&2
  exit 1
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
echo "==> Version: $VERSION  Build: $BUILD_NUMBER"

SCHEME="DraftCanvas"
ARCHIVE="_build/DraftCanvas.xcarchive"
EXPORT_DIR="_build/Export"
EXPORT_OPTS="scripts/ExportOptions.plist"
DMG_PATH="_build/DraftCanvas.dmg"
APPCAST_DIR="_build/appcast"
NOTARY_PROFILE="DC_NOTARY"

SPARKLE_KEY_FILE="${HOME}/.config/sparkle/ed_private_key"
GENERATE_APPCAST="$(command -v generate_appcast 2>/dev/null \
  || find /usr/local/Caskroom/sparkle /opt/homebrew/Caskroom/sparkle -name generate_appcast 2>/dev/null | sort -r | head -1 \
  || true)"
DOWNLOAD_URL_PREFIX="https://github.com/5umm3r/draftcanvas-releases/releases/latest/download/"

if [ -z "$GENERATE_APPCAST" ]; then
  echo "Error: generate_appcast not found. Install via: brew install --cask sparkle" >&2
  exit 1
fi
if [ ! -f "$SPARKLE_KEY_FILE" ]; then
  echo "Error: Sparkle private key not found at $SPARKLE_KEY_FILE" >&2
  echo "       Save the Ed25519 private key (base64) to that file and chmod 600 it." >&2
  exit 1
fi
# quarantine 解除（初回インストール後に必要）
xattr -d com.apple.quarantine "$GENERATE_APPCAST" 2>/dev/null || true

echo "==> Archive"
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo "==> Export"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS"

echo "==> Re-sign embedded binaries (Hardened Runtime)"
SIGN_IDENTITY="Developer ID Application"
BIN_DIR="$EXPORT_DIR/DraftCanvas.app/Contents/Resources/bin"
ENTITLEMENTS="DraftCanvas/DraftCanvas.entitlements"
for f in "$BIN_DIR"/*; do
  [ -f "$f" ] && [ -x "$f" ] || continue
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$f"
done
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$EXPORT_DIR/DraftCanvas.app"

echo "==> Notarize app"
ditto -c -k --keepParent "$EXPORT_DIR/DraftCanvas.app" "$EXPORT_DIR/DraftCanvas.zip"
xcrun notarytool submit "$EXPORT_DIR/DraftCanvas.zip" \
  --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$EXPORT_DIR/DraftCanvas.app"
rm "$EXPORT_DIR/DraftCanvas.zip"

echo "==> Create DMG"
DMG_STAGING=$(mktemp -d)
cp -R "$EXPORT_DIR/DraftCanvas.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "DraftCanvas" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "==> Sign + Notarize DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "==> Generate appcast"
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$APPCAST_DIR"

# generate_appcast が --ed-key-file で署名しない場合の fallback:
# sign_update で署名を取得して enclosure に注入
SIGN_UPDATE="$(dirname "$GENERATE_APPCAST")/sign_update"
xattr -d com.apple.quarantine "$SIGN_UPDATE" 2>/dev/null || true
SIGNATURE=$(cat "$SPARKLE_KEY_FILE" | "$SIGN_UPDATE" "$APPCAST_DIR/DraftCanvas.dmg" | grep -o 'sparkle:edSignature="[^"]*"')
if grep -q 'sparkle:edSignature' "$APPCAST_DIR/appcast.xml"; then
  echo "    Signed by generate_appcast"
elif [ -n "$SIGNATURE" ]; then
  sed -i '' "s|<enclosure url=|<enclosure $SIGNATURE url=|" "$APPCAST_DIR/appcast.xml"
  echo "    Signed via sign_update fallback"
else
  echo "Warning: EdDSA signature could not be generated. Check SPARKLE_KEY_FILE." >&2
fi

echo "==> Upload to GitHub Releases"
RELEASES_REPO="5umm3r/draftcanvas-releases"
TAG="v${VERSION}"
if gh release view "$TAG" --repo "$RELEASES_REPO" &>/dev/null; then
  echo "    Release $TAG exists — uploading assets (overwrite)"
  gh release upload "$TAG" \
    "$DMG_PATH" \
    "$APPCAST_DIR/appcast.xml" \
    --repo "$RELEASES_REPO" \
    --clobber
else
  gh release create "$TAG" \
    "$DMG_PATH" \
    "$APPCAST_DIR/appcast.xml" \
    --repo "$RELEASES_REPO" \
    --title "DraftCanvas $VERSION" \
    --latest
fi

echo "==> Done"
echo "    DMG:     $DMG_PATH"
echo "    appcast: $APPCAST_DIR/appcast.xml"
echo "    Release: https://github.com/$RELEASES_REPO/releases/tag/$TAG"
echo "    Verify:  spctl -a -vvv -t install \"$DMG_PATH\""
