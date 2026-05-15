#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> (e.g. 1.0.0)" >&2
  exit 1
fi

SCHEME="DraftCanvas"
ARCHIVE="_build/DraftCanvas.xcarchive"
EXPORT_DIR="_build/Export"
EXPORT_OPTS="scripts/ExportOptions.plist"
DMG_PATH="_build/DraftCanvas-${VERSION}.dmg"
NOTARY_PROFILE="DC_NOTARY"

echo "==> Archive"
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" archive

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
brew list create-dmg &>/dev/null || brew install create-dmg
create-dmg \
  --volname "DraftCanvas" \
  --window-size 720 400 \
  --background "" \
  --icon "DraftCanvas.app" 240 190 \
  --app-drop-link 480 190 \
  "$DMG_PATH" \
  "$EXPORT_DIR/DraftCanvas.app"

echo "==> Sign + Notarize DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "==> Done: $DMG_PATH"
echo "    Verify: spctl -a -vvv -t install \"$DMG_PATH\""
