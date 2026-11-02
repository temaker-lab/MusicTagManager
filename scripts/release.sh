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
#    자동 업데이트 피드는 zip 아카이브만 대상으로 한다. 사람용 DMG가 dist/에 섞여 있으면
#    generate_appcast가 '중복 아카이브'로 실패하므로, zip만 임시 폴더에 모아 생성한다.
#    generate_appcast는 이전 버전과의 델타(.delta)도 이 폴더에 함께 만든다.
DL_PREFIX="https://github.com/$REPO/releases/download/$FEED_TAG/"
APPCAST_SRC="$(/usr/bin/mktemp -d)"
cp dist/*.zip "$APPCAST_SRC"/
"$GEN_APPCAST" "$APPCAST_SRC" --download-url-prefix "$DL_PREFIX" -o "$APPCAST_SRC/appcast.xml"
cp "$APPCAST_SRC/appcast.xml" dist/appcast.xml

# 5) GitHub Releases: 고정 태그에 zip·델타·appcast.xml 업로드(덮어쓰기)
#    appcast가 참조하는 아카이브(zip·델타)를 모두 올려야 다운로드 404가 없다.
if ! gh release view "$FEED_TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$FEED_TAG" --repo "$REPO" --title "Downloads (appcast)" \
    --notes "자동 업데이트 피드와 모든 버전 아카이브" --latest=false
fi
gh release upload "$FEED_TAG" "$APPCAST_SRC"/*.zip "$APPCAST_SRC/appcast.xml" --repo "$REPO" --clobber
for delta in "$APPCAST_SRC"/*.delta(N); do
  gh release upload "$FEED_TAG" "$delta" --repo "$REPO" --clobber
done
rm -rf "$APPCAST_SRC"

# 5b) 사람이 받는 설치용 DMG ('드래그하여 설치' 창). 자동 업데이트는 위의 zip을 쓴다.
#     웹 다운로드 링크가 버전과 무관하게 고정되도록 자산 이름은 MusicTagManager.dmg 로 올린다.
scripts/make_dmg.sh "$VERSION"
DMG="dist/MusicTagManager.dmg"
cp -f "dist/MusicTagManager-$VERSION.dmg" "$DMG"

# 6) 사람이 받는 '최신(latest)' 릴리스: v$VERSION 태그로 DMG 업로드(덮어쓰기).
#    웹사이트의 .../releases/latest/download/MusicTagManager.dmg 가 항상 최신을 가리킨다.
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber
else
  gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "v$VERSION" \
    --notes "MusicTag Manager v$VERSION" --latest
fi

echo "완료: $VERSION"
echo "  피드:     https://github.com/$REPO/releases/download/$FEED_TAG/appcast.xml"
echo "  다운로드: https://github.com/$REPO/releases/latest"
