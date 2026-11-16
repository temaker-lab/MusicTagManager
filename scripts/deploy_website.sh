#!/bin/zsh
# 웹사이트 배포: website/ 폴더 내용을 gh-pages 브랜치(GitHub Pages) 루트로 올린다.
# 사용: scripts/deploy_website.sh   (main을 먼저 push해 두면 커밋 메시지에 기준 커밋이 남는다)
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
BRANCH="${PAGES_BRANCH:-gh-pages}"
SOURCE_REV="$(git rev-parse --short HEAD)"

git fetch origin "$BRANCH"
WT="$(mktemp -d)"
cleanup() { git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"; }
trap cleanup EXIT
git worktree add --detach "$WT" "origin/$BRANCH" >/dev/null

# website/ 와 똑같이 맞춘다 (gh-pages에만 있는 .nojekyll은 유지 → Jekyll 처리 끔)
rsync -a --delete --exclude '.git' --exclude '.nojekyll' website/ "$WT"/
touch "$WT/.nojekyll"

cd "$WT"
git add -A
if git diff --cached --quiet; then
  echo "웹사이트에 바뀐 내용이 없습니다."
  exit 0
fi
git diff --cached --stat
git commit -q -m "website: deploy from main $SOURCE_REV"
git push origin "HEAD:$BRANCH"
echo "완료: GitHub Pages에 반영되기까지 1~2분 걸릴 수 있습니다."
