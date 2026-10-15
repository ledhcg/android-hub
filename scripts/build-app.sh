#!/bin/bash
# Builds "build/Android Hub.app" (ad-hoc signed) from the SwiftPM package.
#   scripts/build-app.sh [release|debug]
# Environment: ANDROIDHUB_BUNDLE_ID overrides the bundle identifier (default io.github.ledhcg.androidhub);
#              the version comes from the VERSION file.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="${ANDROIDHUB_BUNDLE_ID:-io.github.ledhcg.androidhub}"
APP="build/Android Hub.app"
scripts/fetch-scrcpy-server.sh
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf build/AndroidHub.app "$APP" build/AppIcon.iconset build/AndroidHub_ScrcpyKit.bundle
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/AndroidHub" "$APP/Contents/MacOS/AndroidHub"
# Resource bundles (the pinned scrcpy-server jar lives in AndroidHub_ScrcpyKit.bundle).
for bundle in "$BIN"/*.bundle; do cp -R "$bundle" "$APP/Contents/Resources/"; done

swift scripts/make-icon.swift scripts/assets/AppIconGlyph.png build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Android Hub</string>
    <key>CFBundleDisplayName</key><string>Android Hub</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>AndroidHub</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
cp "$BIN/adbctl" build/adbctl
# adbctl finds the pinned scrcpy-server through the resource bundle that sits next to it.
for bundle in "$BIN"/*.bundle; do cp -R "$bundle" build/; done
echo "Built $APP and build/adbctl"
