#!/bin/bash
# Builds a universal (Apple silicon + Intel) Ribbon.app into dist/, signed ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d.%H%M)}"

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release

APP=dist/Ribbon.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Ribbon" "$APP/Contents/MacOS/Ribbon"
cp "$BIN/ribbon" "$APP/Contents/MacOS/ribbon"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

swift scripts/make_icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (Apple silicon refuses to run unsigned code). Inner tool first, then the app.
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/ribbon"
codesign --force --sign - --timestamp=none --identifier in.thegent.ribbon "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Ribbon"
echo "Built $APP ($VERSION, $BUILD)"
