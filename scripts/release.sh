#!/bin/zsh
# 릴리스: 빌드 → 자체 서명 → zip → appcast.xml(EdDSA 서명) → GitHub Releases 업로드
# 사용: SIGN_IDENTITY="MusicTag Manager Self-Signed" GH_REPO="owner/repo" scripts/release.sh 1.0.0
# 사전 준비는 docs/UPDATES.md 참고 (자체 서명 인증서 · Sparkle generate_keys · gh 로그인).
#
# 호스팅 전략: 모든 버전 zip과 appcast.xml을 '고정 태그(appcast)' 릴리스 하나에 누적 업로드한다.
#   → 다운로드 기준 URL이 안정적(.../releases/download/appcast/)이라 과거 버전 항목도 유효.
#   → dist/ 폴더에 과거 zip을 남겨 두면 generate_appcast가 전체 이력을 포함한 appcast를 만든다.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?사용: scripts/release.sh <version> (예: 1.0.0)}"
: "${SIGN_IDENTITY:?SIGN_IDENTITY 환경변수에 자체 서명 인증서 이름을 지정하세요 (docs/UPDATES.md)}"
REPO="${GH_REPO:-temaker-lab/MusicTagManager}"
FEED_TAG="${FEED_TAG:-appcast}"   # appcast.xml·zip을 모아 두는 고정 릴리스 태그

GEN_APPCAST="$(/usr/bin/find .build -type f -name generate_appcast 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || { echo "generate_appcast를 찾지 못했습니다. 'swift build' 후 다시 시도하세요(Sparkle 아티팩트 필요)."; exit 1; }

# 1) 버전 반영
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist

# 2) 빌드 + 자체 서명 + Sparkle 임베드
SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build_app.sh release

# 3) zip 아카이브 → dist/ (과거 zip 유지)
mkdir -p dist
ARCHIVE="dist/MusicTagManager-$VERSION.zip"
rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/MusicTagManager.app "$ARCHIVE"

# 4) appcast.xml 생성 (EdDSA 개인키는 Keychain에서 자동 사용)
DL_PREFIX="https://github.com/$REPO/releases/download/$FEED_TAG/"
"$GEN_APPCAST" dist --download-url-prefix "$DL_PREFIX" -o dist/appcast.xml

# 5) GitHub Releases: 고정 태그에 zip + appcast.xml 업로드(덮어쓰기)
if ! gh release view "$FEED_TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$FEED_TAG" --repo "$REPO" --title "Downloads (appcast)" \
    --notes "자동 업데이트 피드와 모든 버전 아카이브" --latest=false
fi
gh release upload "$FEED_TAG" "$ARCHIVE" dist/appcast.xml --repo "$REPO" --clobber

# 6) (선택) 사람이 받는 '최신' 릴리스도 별도 태그로 만들고 싶으면 아래 주석 해제
# gh release create "v$VERSION" "$ARCHIVE" --repo "$REPO" --title "v$VERSION" --notes "MusicTag Manager v$VERSION" --latest

echo "완료: $VERSION → https://github.com/$REPO/releases/download/$FEED_TAG/appcast.xml"
