#!/bin/bash
# Builds a universal (Apple silicon + Intel) Ribbon.app into dist/, signed ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-2.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d.%H%M)}"

# One native build per architecture, merged with lipo (more reliable than the multi-arch Xcode build).
for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx13.0"
done
BIN=.build/universal
mkdir -p "$BIN"
for PRODUCT in Ribbon ribbon-cli RibbonFixture; do
  lipo -create -output "$BIN/$PRODUCT" ".build/arm64-apple-macosx/release/$PRODUCT" ".build/x86_64-apple-macosx/release/$PRODUCT"
done

APP=dist/Ribbon.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Ribbon" "$APP/Contents/MacOS/Ribbon"
cp "$BIN/ribbon-cli" "$APP/Contents/Helpers/ribbon"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

swift scripts/make_icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (Apple silicon refuses to run unsigned code). Inner tool first, then the app.
codesign --force --sign - --timestamp=none --identifier in.thegent.ribbon.cli "$APP/Contents/Helpers/ribbon"
codesign --force --sign - --timestamp=none --identifier in.thegent.ribbon "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Ribbon"
echo "Built $APP ($VERSION, $BUILD)"
