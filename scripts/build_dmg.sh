#!/bin/bash
# Packages Haven.app into a drag-to-install DMG with a guided background.
# Usage: scripts/build_dmg.sh path/to/Haven.app path/to/output.dmg
set -euo pipefail
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Retina-ready background (1x + 2x in one TIFF).
tiffutil -cathidpicheck "$ROOT/packaging/dmg-background.png" "$ROOT/packaging/dmg-background@2x.png" -out "$WORK/background.tiff"

# Volume icon from the app icon.
mkdir -p "$WORK/Haven.iconset"
cp "$ROOT"/App/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$WORK/Haven.iconset/"
iconutil -c icns "$WORK/Haven.iconset" -o "$WORK/Haven.icns"

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet "dmgbuild==1.6.7"

rm -f "$OUT"
"$WORK/venv/bin/dmgbuild" \
  -s "$ROOT/packaging/dmg_settings.py" \
  -D app="$APP" \
  -D background="$WORK/background.tiff" \
  -D readme="$ROOT/packaging/Read Me First.pdf" \
  -D icon="$WORK/Haven.icns" \
  "Haven" "$OUT"

echo "Built $OUT"
