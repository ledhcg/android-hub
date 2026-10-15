#!/bin/bash
# Builds build/AndroidHub.app (ad-hoc signed) from the SwiftPM package.
#   scripts/build-app.sh [release|debug]
# Environment: ANDROIDHUB_BUNDLE_ID overrides the bundle identifier (default io.github.ledhcg.androidhub);
#              the version comes from the VERSION file.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="${ANDROIDHUB_BUNDLE_ID:-io.github.ledhcg.androidhub}"
scripts/fetch-scrcpy-server.sh
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf build/AndroidHub.app build/AppIcon.iconset build/AndroidHub_ScrcpyKit.bundle
mkdir -p build/AndroidHub.app/Contents/MacOS build/AndroidHub.app/Contents/Resources

cp "$BIN/AndroidHub" build/AndroidHub.app/Contents/MacOS/AndroidHub
# Resource bundles (the pinned scrcpy-server jar lives in AndroidHub_ScrcpyKit.bundle).
for bundle in "$BIN"/*.bundle; do cp -R "$bundle" build/AndroidHub.app/Contents/Resources/; done

swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AndroidHub.app/Contents/Resources/AppIcon.icns

cat > build/AndroidHub.app/Contents/Info.plist <<PLIST
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

codesign --force --deep --sign - build/AndroidHub.app
cp "$BIN/adbctl" build/adbctl
# adbctl finds the pinned scrcpy-server through the resource bundle that sits next to it.
for bundle in "$BIN"/*.bundle; do cp -R "$bundle" build/; done
echo "Built build/AndroidHub.app and build/adbctl"
