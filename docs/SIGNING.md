# 서명과 공증

## 지금 (Apple Developer 계정 없음)

`scripts/build_app.sh`가 **ad-hoc 서명**(`codesign --sign -`)한다. 내장 `fpcalc`를 먼저 서명하고 앱 전체를 서명한다.

- 이 Mac에서 직접 빌드한 앱은 그대로 실행된다.
- 서명이 빌드마다 바뀌므로 macOS가 **권한(자동화·미디어)을 다시 물을 수 있다**. 키체인 접근은 `/usr/bin/security`로 해서 이 문제를 피했다.
- 다른 Mac에 복사해 쓰려면 받는 쪽에서 `xattr -dr com.apple.quarantine MusicTagManager.app` 후 실행(Gatekeeper가 확인되지 않은 개발자로 막음).
- **계정 없이 공개 배포 + 자동 업데이트**를 하려면 자체 서명 인증서 + Sparkle(EdDSA) + GitHub Releases 방식을 쓴다 → [UPDATES.md](UPDATES.md).

## 계정이 생기면 (Developer ID + 공증)

1. Xcode > Settings > Accounts에서 팀을 추가하고 **Developer ID Application** 인증서를 만든다.
2. 공증용 앱 암호를 키체인에 저장한다 (한 번):
   ```bash
   xcrun notarytool store-credentials MusicTagManager --apple-id <Apple ID> --team-id <TEAM_ID>
   ```
3. 서명·공증·스테이플:
   ```bash
   scripts/notarize.sh "Developer ID Application: 이름 (TEAM_ID)" MusicTagManager
   ```
   스크립트는 Hardened Runtime(`--options runtime`)과 `Resources/MusicTagManager.entitlements`
   (`com.apple.security.automation.apple-events`)로 서명하고, zip을 `notarytool submit --wait`로 제출한 뒤 `stapler staple`한다.
   **임베드된 Sparkle.framework와 그 안의 XPC 서비스·헬퍼(`Autoupdate`·`Updater.app`)도 안쪽부터 Developer ID로 자동 재서명**한다(공증 통과 필수).
4. Developer ID로 서명하면 서명이 고정되어 **빌드마다 권한을 다시 묻지 않는다.** 공증 후에는 자동 업데이트도 최초 설치 경고 없이 동작한다(피드·키 설정은 [UPDATES.md](UPDATES.md)).

ShazamKit은 App ID에 ShazamKit App Service를 켜야 쓸 수 있다. 계정이 생겨도 현재 구현은 AcoustID를 쓴다(Phase 0 결정).
