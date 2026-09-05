#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP_NAME="HalideViewer"
APP_BUNDLE="./${APP_NAME}.app"

echo "Assembling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp ".build/release/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "Sources/HalideViewer/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ "${1:-}" == "--install" ]; then
  DEST="/Applications/${APP_NAME}.app"
  echo "Installing to ${DEST}..."
  rm -rf "$DEST"
  cp -R "$APP_BUNDLE" "$DEST"
  "$LSREGISTER" -f "$DEST"
  echo "Installed. Launch with: open \"$DEST\""
else
  "$LSREGISTER" -f "$APP_BUNDLE"
  echo "Built at $APP_BUNDLE (not installed to /Applications)."
  echo "Re-run with --install to copy it to /Applications and register it there."
fi
