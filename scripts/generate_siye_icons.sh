#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGO="$ROOT_DIR/web/canvas-host/public/siye-logo.svg"
MAC_LOGO="$ROOT_DIR/design/siye-macos-icon.svg"
IOS_ICONS="$ROOT_DIR/apps/ios/Sources/ExcalidrawIOS/Resources/Assets.xcassets/AppIcon.appiconset"
IOS_LOGO="$ROOT_DIR/apps/ios/Sources/ExcalidrawIOS/Resources/Assets.xcassets/SiyeLogo.imageset/siye-logo.png"
MAC_ICONS="$ROOT_DIR/apps/macos/Sources/ExcalidrawMac/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to generate Siye app icons." >&2
  exit 1
fi

render_icon() {
  local size="$1"
  local output="$2"
  local source="${3:-$LOGO}"
  rsvg-convert -w "$size" -h "$size" "$source" -o "$output"
}

while read -r filename size; do
  render_icon "$size" "$IOS_ICONS/$filename.png"
done <<'ICONS'
20 20
20@2x-ipad 40
20@2x 40
20@3x 60
29 29
29@2x-ipad 58
29@2x 58
29@3x 87
40 40
40@2x-ipad 80
40@2x 80
40@3x 120
60@2x 120
60@3x 180
76 76
76@2x 152
83.5@2x 167
1024 1024
ICONS

render_icon 512 "$IOS_LOGO"

while read -r filename size; do
  render_icon "$size" "$MAC_ICONS/$filename.png" "$MAC_LOGO"
done <<'ICONS'
16 16
16@2x 32
32 32
32@2x 64
128 128
128@2x 256
256 256
256@2x 512
512 512
512@2x 1024
ICONS
