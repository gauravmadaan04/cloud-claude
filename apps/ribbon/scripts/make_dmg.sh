#!/bin/bash
# Packages dist/Ribbon.app into dist/Ribbon-<version>.dmg with an install guide, plus a zip.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-2.0.0}"

swift scripts/make_dmg_background.swift dist
tiffutil -cathidpicheck dist/dmg-background.png dist/dmg-background@2x.png -out dist/dmg-background.tiff
cp "Resources/Read Me First.html" "dist/Read Me First.html"

if [ ! -x /tmp/dmgvenv/bin/dmgbuild ]; then
  python3 -m venv /tmp/dmgvenv
  /tmp/dmgvenv/bin/pip install --quiet dmgbuild
fi
rm -f "dist/Ribbon-$VERSION.dmg"
/tmp/dmgvenv/bin/dmgbuild -s scripts/dmg_settings.py \
  -D app=dist/Ribbon.app -D bg=dist/dmg-background.tiff -D "readme=dist/Read Me First.html" \
  -D icon=dist/Ribbon.app/Contents/Resources/AppIcon.icns \
  "Ribbon $VERSION" "dist/Ribbon-$VERSION.dmg"
hdiutil verify "dist/Ribbon-$VERSION.dmg"
(cd dist && ditto -c -k --keepParent Ribbon.app "Ribbon-$VERSION.zip")
ls -la dist
