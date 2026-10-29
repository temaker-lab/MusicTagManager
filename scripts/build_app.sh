#!/bin/zsh
# MusicTagManager.app 조립 + 서명 + Sparkle(자동 업데이트) 임베드
# 사용: scripts/build_app.sh [release|debug]
#   로컬 실행:   그냥 실행 → ad-hoc 서명("-")
#   배포(자동 업데이트): SIGN_IDENTITY="자체 서명 인증서 이름" scripts/build_app.sh release
#     (자체 서명 인증서는 고정 신원이라 Sparkle이 업데이트 서명 일관성 검사를 통과한다. docs/UPDATES.md 참고)
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIG="${1:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c "$CONFIG" --product MusicTagManager
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/MusicTagManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MusicTagManager" "$APP/Contents/MacOS/MusicTagManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/bin"
cp Resources/bin/fpcalc "$APP/Contents/Resources/bin/fpcalc"

# --- Sparkle.framework 임베드 (자동 업데이트) ---
SPARKLE_FW=""
for cand in \
  "$BIN_DIR/Sparkle.framework" \
  "$(/usr/bin/find .build -type d -name 'Sparkle.framework' -path '*macos*' 2>/dev/null | head -1)" \
  "$(/usr/bin/find .build -type d -name 'Sparkle.framework' 2>/dev/null | head -1)"; do
  if [ -n "$cand" ] && [ -d "$cand" ]; then SPARKLE_FW="$cand"; break; fi
done
if [ -n "$SPARKLE_FW" ]; then
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
  # 실행 파일이 ../Frameworks를 찾도록 rpath 보강 (이미 있으면 무시)
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/MusicTagManager" 2>/dev/null || true
  echo "Sparkle 임베드: $SPARKLE_FW"
else
  echo "⚠️  Sparkle.framework를 찾지 못했습니다. 자동 업데이트 없이 패키징합니다."
fi

# --- 서명: 안쪽부터(fpcalc → Sparkle 내부 헬퍼 → 프레임워크 → 앱) ---
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/bin/fpcalc"
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  for item in \
    "$FW/Versions/B/XPCServices/Downloader.xpc" \
    "$FW/Versions/B/XPCServices/Installer.xpc" \
    "$FW/Versions/B/Autoupdate" \
    "$FW/Versions/B/Updater.app"; do
    [ -e "$item" ] && codesign --force --sign "$SIGN_IDENTITY" "$item"
  done
  codesign --force --sign "$SIGN_IDENTITY" "$FW"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --verbose=1 "$APP"
echo "완료: $PWD/$APP  (서명: $SIGN_IDENTITY)"
