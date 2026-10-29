# 자동 업데이트 (Sparkle + 자체 서명 + GitHub Releases)

Apple 개발자 계정 없이 자동 업데이트를 제공한다. 업데이트 무결성은 **EdDSA 자체 키**로 보장하고,
배포 신원은 **자체 서명(self-signed) 코드서명 인증서**로 고정한다(Sparkle의 서명 일관성 검사 통과용).

> 한계: 공증이 없으므로 **최초 설치 때 한 번** 사용자가 "확인되지 않은 개발자"를 우클릭 → 열기(또는
> `xattr -dr com.apple.quarantine MusicTagManager.app`) 해야 한다. 이후 Sparkle 업데이트는 경고 없이 자동 설치된다.

## 1회 준비

### A. 자체 서명 코드서명 인증서 만들기
키체인 접근 → 인증서 지원 → 인증서 생성:
- 이름: `MusicTag Manager Self-Signed`
- 신원 유형: **자체 서명 루트(Self-Signed Root)**
- 인증서 유형: **코드 서명(Code Signing)**
만든 뒤 이 이름을 `SIGN_IDENTITY`로 쓴다. (고정 신원이라 매 빌드 서명이 같아 Sparkle 검사를 통과)

### B. Sparkle EdDSA 키 생성
```bash
swift build                       # Sparkle 아티팩트 내려받기(한 번)
GEN_KEYS="$(find .build -type f -name generate_keys | head -1)"
"$GEN_KEYS"                        # 개인키는 Keychain에 저장되고, 공개키(base64)를 출력
```
출력된 **공개키**를 `Resources/Info.plist`의 `SUPublicEDKey` 값에 붙여 넣는다.
개인키는 **Keychain에만** 있으며 절대 공유/커밋하지 않는다(릴리스 때 자동으로 서명에 쓰임).

### C. Info.plist 값 교체
- `SUPublicEDKey` → 위에서 얻은 공개키
- `SUFeedURL` → 이미 `https://github.com/temaker-lab/MusicTagManager/releases/download/appcast/appcast.xml` 로 설정됨(저장소가 바뀌면 교체)
(공개키가 placeholder면 앱의 '업데이트 확인' 메뉴·설정이 **자동으로 숨겨진다** → 실행 오류 없음. 공개키를 채우면 활성화)

### D. GitHub CLI 로그인
```bash
gh auth login
```

## 릴리스 절차 (매 버전)
```bash
SIGN_IDENTITY="MusicTag Manager Self-Signed" scripts/release.sh 1.0.0   # GH_REPO 기본값: temaker-lab/MusicTagManager
```
스크립트가 하는 일:
1. `Info.plist`의 버전(CFBundleShortVersionString/CFBundleVersion) 갱신
2. `build_app.sh`로 빌드 + 자체 서명 + **Sparkle.framework 임베드/서명**
3. `.app`을 zip으로 압축해 `dist/`에 보관(과거 zip 유지 → 이력 포함)
4. `generate_appcast`로 `dist/appcast.xml` 생성(EdDSA 서명, Keychain 개인키 사용)
5. 고정 태그 릴리스 **`appcast`** 에 zip + appcast.xml 업로드(덮어쓰기)

> 모든 버전의 zip과 appcast.xml이 `releases/download/appcast/` 한 곳에 모여, `SUFeedURL`이 항상 유효하다.
> `dist/` 폴더는 지우지 말 것(과거 아카이브가 있어야 appcast 이력이 유지됨). 새 PC에서 릴리스하면
> 기존 릴리스의 zip들을 `dist/`로 먼저 내려받은 뒤 실행한다.

## 사용자 경험
- **최초 설치**: 다운로드한 .app은 "확인되지 않은 개발자" 경고 → 우클릭 → 열기(1회).
- **이후 업데이트**: 앱 메뉴 `MusicTag Manager → 업데이트 확인…` 또는 설정 → 일반 → 도움말 → 업데이트,
  그리고 하루 1회 자동 확인(Info.plist `SUEnableAutomaticChecks`/`SUScheduledCheckInterval`). Sparkle이 받아 교체·재실행.

## 웹사이트
`website/app.js`의 `DOWNLOAD_URL`은 이미 `https://github.com/temaker-lab/MusicTagManager/releases/latest` 로 설정됨.

## 나중에 Apple Developer ID가 생기면
`docs/SIGNING.md`의 공증 절차(`notarize.sh`)로 바꾸면 최초 설치 경고까지 사라진다. Sparkle 설정은 그대로 두고
`SIGN_IDENTITY`만 "Developer ID Application: …"로 바꾸면 된다.
