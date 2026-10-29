#!/bin/zsh
# Developer ID 서명 + 공증 + 스테이플 (Apple Developer 계정이 생겼을 때 사용)
# 사용: scripts/notarize.sh "Developer ID Application: 이름 (TEAM_ID)" <notarytool 키체인 프로필>
#
# build_app.sh가 Sparkle.framework를 임베드하므로, 공증을 통과하려면 fpcalc·Sparkle(XPC·헬퍼·프레임워크)·앱을
# 모두 Developer ID + Hardened Runtime(--options runtime) + 보안 타임스탬프(--timestamp)로 '안쪽부터' 다시 서명한다.
set -euo pipefail
cd "${0:A:h}/.."
IDENTITY="${1:?서명 ID가 필요합니다}"
PROFILE="${2:?notarytool store-credentials 프로필 이름이 필요합니다}"

# 1) 번들 조립 + Sparkle 임베드 (여기서의 ad-hoc 서명은 아래에서 Developer ID로 덮어쓴다)
scripts/build_app.sh release
APP="build/MusicTagManager.app"

SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")

# 2) 안쪽부터 서명: fpcalc → Sparkle(XPC 서비스·Autoupdate·Updater.app·프레임워크) → 앱(엔타이틀먼트)
"${SIGN[@]}" "$APP/Contents/Resources/bin/fpcalc"

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  for item in \
    "$FW/Versions/B/XPCServices/Downloader.xpc" \
    "$FW/Versions/B/XPCServices/Installer.xpc" \
    "$FW/Versions/B/Autoupdate" \
    "$FW/Versions/B/Updater.app"; do
    [ -e "$item" ] && "${SIGN[@]}" "$item"
  done
  "${SIGN[@]}" "$FW"
else
  echo "참고: Sparkle.framework가 없어 자동 업데이트 없이 공증합니다."
fi

# 앱 본체는 엔타이틀먼트(자동화 Apple Events)와 함께 마지막에 서명
codesign --force --options runtime --timestamp \
  --entitlements Resources/MusicTagManager.entitlements --sign "$IDENTITY" "$APP"

# 중첩 코드까지 유효한지 엄격 검증
codesign --verify --deep --strict --verbose=2 "$APP"

# 3) zip → 공증 제출(대기) → 스테이플 → Gatekeeper 확인
ZIP="build/MusicTagManager.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
echo "공증 완료: $APP"
