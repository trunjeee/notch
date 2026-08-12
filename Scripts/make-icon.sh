#!/bin/bash
# Builds Resources/AppIcon.icns from a single 1024x1024 master PNG.
# Usage: Scripts/make-icon.sh [path-to-master.png]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="${1:-$ROOT/Resources/AppIconMaster.png}"
OUT="$ROOT/Resources/AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"

if [ ! -f "$MASTER" ]; then
    echo "!!! master image not found: $MASTER" >&2
    echo "    save a 1024x1024 PNG there (or pass a path as the first argument)" >&2
    exit 1
fi

mkdir -p "$ICONSET"

for spec in \
    "16 icon_16x16" "32 icon_16x16@2x" \
    "32 icon_32x32" "64 icon_32x32@2x" \
    "128 icon_128x128" "256 icon_128x128@2x" \
    "256 icon_256x256" "512 icon_256x256@2x" \
    "512 icon_512x512" "1024 icon_512x512@2x"
do
    set -- $spec
    sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$(dirname "$ICONSET")"

echo "==> wrote $OUT"
