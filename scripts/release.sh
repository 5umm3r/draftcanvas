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

if ! command -v generate_appcast &>/dev/null; then
  echo "Error: generate_appcast not found. Install via: brew install --cask sparkle" >&2
  exit 1
fi

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
generate_appcast "$APPCAST_DIR"

echo "==> Done"
echo "    DMG:     $DMG_PATH"
echo "    appcast: $APPCAST_DIR/appcast.xml"
echo ""
echo "Next: upload to GitHub Releases v$VERSION (5umm3r/draftcanvas-releases):"
echo "  - _build/DraftCanvas.dmg"
echo "  - _build/appcast/appcast.xml"
echo "    Verify: spctl -a -vvv -t install \"$DMG_PATH\""
