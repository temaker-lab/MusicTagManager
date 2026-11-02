#!/bin/zsh
# build/MusicTagManager.app → '드래그하여 설치' DMG (dist/MusicTagManager-<version>.dmg)
# create-dmg(brew)가 있으면 배경·아이콘 배치가 있는 설치 안내 창을, 없으면 기본 DMG를 만든다.
# 사용: scripts/make_dmg.sh <version>   (먼저 scripts/build_app.sh 로 앱을 만들어 둘 것)
set -euo pipefail
cd "${0:A:h}/.."
VERSION="${1:?사용: scripts/make_dmg.sh <version>}"
APP="build/MusicTagManager.app"
[ -d "$APP" ] || { echo "먼저 scripts/build_app.sh 로 $APP 를 만드세요"; exit 1; }
mkdir -p dist
DMG="dist/MusicTagManager-$VERSION.dmg"
rm -f "$DMG"

if command -v create-dmg >/dev/null 2>&1; then
  bg_opt=()
  [ -f Resources/dmg-background.png ] && bg_opt=(--background Resources/dmg-background.png)
  create-dmg \
    --volname "MusicTag Manager" \
    "${bg_opt[@]}" \
    --window-pos 200 120 \
    --window-size 660 420 \
    --icon-size 120 \
    --icon "MusicTagManager.app" 165 185 \
    --hide-extension "MusicTagManager.app" \
    --app-drop-link 495 185 \
    --no-internet-enable \
    "$DMG" "$APP"
else
  echo "⚠️  create-dmg가 없어 배경 없는 기본 DMG를 만듭니다. 설치 안내 화면을 원하면: brew install create-dmg"
  stage="$(mktemp -d)"
  cp -R "$APP" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "MusicTag Manager" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$stage"
fi
echo "완료: $PWD/$DMG"
