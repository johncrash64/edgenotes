#!/bin/bash
# scripts/package.sh — assemble build/EdgeNotes.app
#
#   ./scripts/package.sh
#   CODESIGN_IDENTITY="My Cert" ./scripts/package.sh
#   VERSION=7 SHORT=1.1 ./scripts/package.sh
#
# Signing: with no CODESIGN_IDENTITY the app is signed ad-hoc, which works but
# makes macOS treat every build as a different app. A stable identity (any
# code-signing certificate in your login keychain) avoids that. No
# notarization, no hardened runtime: this is meant to be built and run locally.
set -euo pipefail

BUNDLE_ID="com.johncrash64.edgenotes"
APP_NAME="EdgeNotes"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/$APP_NAME.app"
VERSION="${VERSION:-1}"
SHORT="${SHORT:-0.1.0}"

echo "▸ Building release binary…"
cd "$PROJECT_ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ Assembling $APP_BUNDLE …"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/EdgeNotesApp" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "▸ Signing with: $([ "$IDENTITY" = "-" ] && echo "ad-hoc" || echo "$IDENTITY")"
codesign -s "$IDENTITY" --force --timestamp=none "$APP_BUNDLE"

echo "▸ Verifying bundle…"
codesign --verify --strict "$APP_BUNDLE"
test -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "✓ $APP_BUNDLE (v$SHORT build $VERSION)"
echo "  Run it:  open \"$APP_BUNDLE\""
