#!/usr/bin/env bash
# Build Assets/AppIcon.icns from the DeepSeek black-whale vector (Assets/whale-icon.svg).
# Uses only built-in macOS tools: qlmanage (SVG raster), sips (resize), iconutil (icns).
set -euo pipefail
cd "$(dirname "$0")"

SVG="Assets/whale-icon.svg"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" Assets

# 1) Rasterize the vector to a crisp 1024 master.
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
MASTER="$WORK/whale-icon.svg.png"
[ -f "$MASTER" ] || { echo "rasterize failed"; exit 1; }

gen(){ # size outfile
  sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null
}
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

# 2) Assemble the multi-resolution .icns.
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
rm -rf "$WORK"
echo "Icon built: Assets/AppIcon.icns"
