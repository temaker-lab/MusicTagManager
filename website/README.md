# MusicTag Manager — 소개/다운로드 웹사이트

정적(HTML/CSS/JS) 사이트입니다. 빌드 과정이나 서버가 필요 없습니다.

## 구성
- `index.html` — 페이지 구조(히어로 · 사용법 · 기능 · 개인정보 · 설치 · FAQ · 푸터)
- `styles.css` — 라이트·미니멀 스타일
- `app.js` — 한국어/English 토글(브라우저 언어 자동 감지), 연도, 다운로드 링크 연결
- `assets/icon.png` — 앱 아이콘(512px, `Resources/AppIcon.icns`에서 변환)

## 로컬 미리보기
```bash
cd website
python3 -m http.server 8080
# 브라우저에서 http://localhost:8080 열기
```
(또는 `index.html`을 브라우저로 바로 열어도 됩니다.)

## 배포 전 반드시 바꿀 것
1. **다운로드 링크** — `app.js` 맨 위의 `DOWNLOAD_URL`을 실제 DMG/릴리스 주소로 교체하세요.
   ```js
   const DOWNLOAD_URL = "https://github.com/<owner>/<repo>/releases/latest";
   // 또는 직접 호스팅한 .dmg 링크
   ```
   미설정(`"#install"`) 상태에서는 다운로드 버튼이 설치 섹션으로 스크롤만 합니다(깨진 링크 아님).

## (선택) 실제 앱 스크린샷 넣기
현재 ‘사용법’은 아이콘·텍스트 카드로 구성돼 있습니다. 실제 캡처 이미지를 쓰고 싶으면
`assets/`에 PNG를 넣고 `index.html`의 각 step/card에 `<img>`를 추가하면 됩니다.

## 배포처
정적 호스팅 어디든 `website/` 폴더를 올리면 됩니다.
- Cloudflare Pages / Workers(현재 참고 도메인과 동일 계열), GitHub Pages, Netlify, Vercel 등
- 예) Cloudflare Pages: 이 폴더를 프로젝트 루트로 지정, 빌드 명령 없음, 출력 디렉터리 `website`

## 문구/언어
- 모든 텍스트는 `app.js`의 `i18n.ko` / `i18n.en` 딕셔너리에 있습니다. 여기만 고치면 양쪽 언어가 반영됩니다.
- 연락처: `rnap.00@gmail.com` (`index.html` 푸터).
