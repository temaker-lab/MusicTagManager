#!/bin/bash
# 1024px PNG로 앱 아이콘(Resources/AppIcon.icns)을 만든다.
# 사용: scripts/set_app_icon.sh [Resources/IconSamples/icon-A-tag.png]
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-Resources/IconSamples/icon-A-tag.png}"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "앱 아이콘: $SOURCE → Resources/AppIcon.icns (./scripts/build_app.sh로 다시 빌드하세요)"
