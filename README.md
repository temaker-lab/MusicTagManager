# MusicTag Manager

선택한 Music 플레이리스트에서 **앨범커버·곡 제목·가수명·앨범명 중 하나라도 비어 있는 곡만** 찾아 빈 정보를 자동으로 채우고, 확신이 없는 곡만 모아서 한 번에 확인받는 개인용 macOS 앱.

> 개발 중 안전장치: **곡이 3,000개를 넘는 보관함에는 쓰지 않는다** (설정 > 일반). 테스트 보관함에서 확인을 마친 뒤 끈다.

## 설치

요구 사항: macOS 14 이상(Apple Silicon), 빌드용 Xcode.

```bash
scripts/build_app.sh                         # build/MusicTagManager.app (ad-hoc 서명, fpcalc 포함)
cp -R build/MusicTagManager.app /Applications/
open /Applications/MusicTagManager.app
```

- `xcode-select`가 Command Line Tools를 가리켜도 스크립트가 `DEVELOPER_DIR`로 Xcode를 쓴다.
- `build_app.sh`는 **Sparkle 자동 업데이트 프레임워크를 임베드·서명**한다(배포 빌드). 자동 업데이트 설정 전에는 앱의 ‘업데이트 확인’ UI가 비활성화된다.
- Apple Developer 계정 없이 ad-hoc 서명하므로 **다시 빌드하면 macOS가 다른 앱으로 보고 권한을 다시 묻는다.**

## 배포와 자동 업데이트

| 상황 | 방법 | 결과 |
|---|---|---|
| 개인용 (지금) | `scripts/build_app.sh` (ad-hoc) | 이 Mac에서 바로 실행 |
| 공개 배포 (계정 없음) | `scripts/release.sh` — 자체 서명 + Sparkle(EdDSA) + GitHub Releases | 최초 1회 수동 허용 후 **자동 업데이트** |
| 공개 배포 (Developer ID) | `scripts/notarize.sh` — 서명·공증(Sparkle 포함) | Gatekeeper 경고 없음 |

- 자동 업데이트 설정(자체 서명 인증서 · Sparkle 키 · 릴리스 절차)은 **[docs/UPDATES.md](docs/UPDATES.md)**, Developer ID 서명·공증은 **[docs/SIGNING.md](docs/SIGNING.md)**.
- 소개·다운로드 웹사이트(한국어·English)는 `website/`(정적 사이트). 배포 전 `app.js`의 `DOWNLOAD_URL`과 `Info.plist`의 `SUFeedURL`에서 `OWNER/REPO`를 교체한다.
- 앱 UI는 **한국어·English**를 지원한다(설정 > 일반 > 언어, 즉시 전환).

## 처음 실행 (온보딩)

1. **권한 2개** — 한 번만 묻는다.

   | 권한 | 용도 | 거부했다면 |
   |---|---|---|
   | Music 앱 제어 (Apple Events) | 곡 정보·커버 기록, 기록 후 재확인 | 시스템 설정 > 개인정보 보호 및 보안 > 자동화 |
   | 미디어 및 Apple Music | 보관함 읽기 (XML 내보내기 불필요) | 시스템 설정 > 개인정보 보호 및 보안 > 미디어 및 Apple Music |

2. **대상 플레이리스트** 선택 — 폴더를 고르면 하위 플레이리스트 전체. 각 항목에 “곡 수 · 정리 필요 곡 수”.
3. ‘시작’을 누르면 바로 검사한다. 식별은 대시보드의 ‘식별 실행’으로 시작한다.

AcoustID(오디오 지문)를 쓰려면 acoustid.org/new-application 에서 무료 키를 받아 **설정 > 식별**에 넣는다. 키가 없으면 지문 없이 텍스트 검색만 한다.

## 사용법

모든 변경은 사용자가 직접 실행한다 (자동 정리 없음).

1. **검사** — 앱을 열면 선택한 플레이리스트에서 4개 항목 중 하나라도 빈 곡을 찾는다. ‘다시 검사’(⌘R)는 바뀐 곡만 다시 판정.
2. **식별 실행** — 커버 상태 확인(ITLibrary가 커버가 있다고 한 정리 대상 곡을 Music에서 직접 확인) → MusicBrainz·iTunes·AcoustID로 앨범 단위 식별 → 커버 후보 미리 확인. 진행 표시줄은 단계마다 새로 센다.
3. **검토·적용** — 검토 대기함이나 식별 결과에서 확인하고 승인·선택 적용·전체 적용.

| 화면 | 할 수 있는 일 |
|---|---|
| 대시보드 상단 | 알약 탭(검토 대기함·식별 결과·곡 목록·작업 이력), 테마 전환(다크·시스템·기본), 대상 플레이리스트, 다시 검사 |
| 개요 카드 | 범위 내 곡(완비율 링) · 누락 항목 도넛(누르면 곡 목록 필터) · 식별 결과 막대(누르면 신뢰도 필터)와 식별 실행 · 적용 현황(정리 완료·검토 대기·적용 실패·식별 실패) |
| 검토 대기함 | 앨범 카드(현재 커버 → 제안 커버, 앨범명, 바뀔 항목, 신뢰도). 승인·거절·자세히, 높음·보통 전부 승인. **↑↓ 이동 · Return/더블클릭 자세히 · ⌘Return 승인 · Delete 거절**. 이미지를 카드에 끌어 놓으면 그 앨범의 커버 없는 곡에 지정 |
| 앨범 상세 | 곡별 현재값 ↔ 제안값(바뀌는 칸만 진하게), 더블클릭으로 직접 수정, 커버 끌어 놓기 |
| 식별 결과 | 신뢰도 필터·검색, ‘적용 시 변경’ 미리보기, 선택 적용 · 전체 적용(필터·검색 기준), 직접 수정, **검수표 CSV 내보내기·가져오기** |
| 직접 수정 | 제목·가수·앨범·앨범 아티스트·장르·연도·트랙/디스크 번호·커버(파일 선택·끌어 놓기·붙여넣기). 입력한 값은 기존 값과 달라도 쓴다 |
| 작업 이력 | 작업별·앨범별·곡별 결과와 사유, 되돌리기, 끝나지 않은 작업 이어서 실행·취소 |

**상태 색**: 적용 완료(초록) · 적용 실패(빨강, 누르면 사유) · 검토 대기(노랑) · 직접 수정(파랑) · 식별 실패/바꿀 값 없음/거절(회색).
‘식별 실행’을 누르면 직접 수정을 뺀 모든 상태가 검토 대기로 초기화된다.
**대상 플레이리스트를 바꾸면** 작업 이력·정리 완료 수·식별 결과가 초기화된다(이전 변경은 앱에서 되돌릴 수 없게 되므로 확인 창이 뜬다).
**화면 테마**: 설정 > 일반 > 화면, 또는 상단 오른쪽 버튼에서 다크 · 시스템 설정 · 기본.

### 검수표 (CSV)
식별 결과 > 검수표 > **CSV로 내보내기** → 엑셀·Numbers에서 ‘결정’ 열에 `승인`/`거절`을 적거나 ‘제안 …’ 열을 고친다 → **CSV 가져오기**.
고친 값은 ‘직접 수정’으로, 거절은 바로 반영되고, 승인한 곡은 확인 후 적용한다. UTF-8 BOM CSV라 엑셀에서 한글이 깨지지 않는다.

## 무엇을 바꾸고 무엇을 안 바꾸나

- 선택하지 않은 플레이리스트의 곡, 4개 항목이 모두 채워진 곡은 **건드리지 않는다**.
- **판정**: 텍스트는 NFC 정규화·공백 제거 후 판정. 플레이스홀더(`Unknown Artist`, `알 수 없는 앨범 (날짜)`, `여러 음악가`, `Track 01` 등)는 빈 값. 제목이 파일명과 같다는 것만으로는 빈 값으로 보지 않는다(Music이 파일명을 제목으로 바꿔 두므로). `아티스트 - 제목`·`05 제목` 형태이면서 가수명이나 앨범명도 비면 빈 값.
- **쓰기 정책**(설정 > 쓰기 정책): 기본은 곡 제목·가수명·앨범명 = ‘다르면 교체’, 나머지(커버 포함) = ‘비어 있을 때만’. 필드별로 바꿀 수 있고 ‘모두 비어 있을 때만’으로 되돌릴 수 있다.
- ITLibrary는 곡에 커버가 없어도 같은 앨범의 캐시 이미지를 ‘있다’고 보고할 때가 있다. 그래서 커버를 채울지는 쓰기 직전 Music에서 읽은 값으로 정하고, 읽은 값은 기억해 다음 검사에 쓴다.
- 곡 단위로 식별한 릴리스가 로컬 앨범과 다르면 커버·트랙 번호·연도는 제안하지 않는다(다른 앨범 커버가 들어가는 것 방지).
- 태그가 바뀌면 Music의 “미디어 폴더 정리”에 따라 파일이 `가수/앨범/` 폴더로 이동·개명된다(의도된 동작). 되돌리면 원래 위치로 돌아간다.
- 클라우드 전용·파일 없음·음악이 아닌 항목은 수정하지 않는다. 재생 중인 곡도 재생을 방해하지 않고 쓴다.

## 되돌리기

- 모든 변경은 쓰기 직전에 **스냅샷**(바꾸기 전 태그·커버 수, 교체되는 커버는 원본 이미지)을 남긴다. 스냅샷 없이 쓰는 경로는 코드에 없다(`LibraryWriter`는 `Snapshot`이 있어야 호출 가능하고 `Snapshot`은 Core 모듈 안에서만 생성).
- 곡마다 ① Music에서 최신 값을 다시 읽고 ② 검사 이후 직접 고친 곡이면 건너뛰고 ③ 스냅샷 저장 ④ 쓰기 ⑤ 다시 읽어 검증한다.
- 대시보드 > 작업 이력 > **이 작업 전체 되돌리기 / 이 앨범만 / 이 곡만**. 되돌리기도 작업으로 기록되고, 다시 읽어 검증한다. 적용 이후 사용자가 직접 고친 값은 덮어쓰지 않고 건너뛴다.
- 앱이 중간에 꺼지면 다음 실행 때 끝나지 않은 작업을 이어서 한다(쓰다가 멈춘 곡은 기록해 둔 같은 변경을 다시 적용).
- (선택) 설정 > 일반 > **원본 음악 파일 전체 백업**: 쓰기 전 원본 파일을 `Backup/Files/job<번호>/`에 복사한다(APFS 복제라 바뀐 부분만큼만 용량을 씀). 자동 복원은 하지 않으므로 필요하면 Finder에서 직접 되돌린다.
- **스냅샷 보존 기간**(설정 > 일반 > 안전, 기본 30일): 기간이 지난 스냅샷과 백업 파일은 앱 실행 시 자동 정리된다(디스크 사용 억제). 정리된 작업은 되돌리기가 비활성화된다. ‘무제한’이면 보관한다. 재개가 필요한 미완료 작업은 정리하지 않는다.

## 식별 엔진

| 소스 | 용도 | 제한 |
|---|---|---|
| MusicBrainz | 릴리스·트랙리스트·한글 별칭 (기본 소스) | 초당 1회, User-Agent에 연락처 |
| AcoustID + fpcalc | 오디오 지문 (녹음과 수록 릴리스까지 한 번에) | 초당 3회, API 키 필요 |
| iTunes Search (US) | 커버 1200px, 트랙 길이로 교차 확인 | 분당 약 20회, 필요할 때만 |
| Cover Art Archive | 커버 | — |

- 릴리스 선택: 컴필레이션·라이브·리믹스·Various Artists 제외 → 한국 곡이면 한글 제목 → Album > EP > Single → 최초 발매일. 기존 앨범명이나 파일명의 앨범명이 있으면 그 앨범을 먼저 고른다.
- 신뢰도(0~100, `ConfidenceWeights`): 지문 +40, 제목 +20/+12, 가수 +15/+8, 길이 3초 이내 +10, 트랙 수 +10, 소스 일치 +10, 앨범명 +10, 같은 앨범 곡의 지문 확인 +25, 후보 경합 −20, 기존·파일명 단서와 불일치 −30. 높음 ≥ 80, 보통 55~79. 지문 없이 텍스트만 완벽히 맞으면 75점(보통).
- AcoustID는 한 지문에 다른 녹음을 묶기도 해서, 제목(기존 값 또는 파일명 단서)이 맞는 지문 녹음만 믿는다.
- 모든 응답은 `api_cache`에 30일 보관한다.

## 테스트 보관함에서 먼저 확인하기

1. Music 종료 → **Option 키를 누른 채** Music 실행 → “새로운 보관함 생성” (예: `~/Music/test`)
2. 음악 파일 몇십 곡(복사본 권장)을 추가하고 앱에서 적용·되돌리기를 확인
3. 끝나면 Option 키를 누른 채 Music 실행 → 원래 보관함 선택

명령줄 점검 도구 (⚠️ 테스트 보관함 전용, 곡 3,000개 초과면 자동 중단):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release MTMApplyCheck --db /tmp/mtm-check.sqlite --dry-run apply test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release MTMApplyCheck --db /tmp/mtm-check.sqlite undo
```

## 개발

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test                         # 단위·통합 테스트
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release MTMBench       # 실제 보관함 목록화 성능 (읽기 전용)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release MTMIdentify --limit 10 "플레이리스트"  # 식별 결과 점검
```
### Xcode

`MusicTagManager.xcodeproj`를 열고 **MusicTag Manager** 스킴으로 ⌘R(실행)·⌘B(빌드)·Product > Archive.

- 앱 타깃은 `Sources/MusicTagManager` 폴더를 그대로 동기화한다 (Xcode에서 파일을 추가·삭제하면 폴더에 반영됨).
- 핵심 로직은 같은 폴더의 Swift 패키지(`Package.swift`)의 `MTMCore` 라이브러리를 링크한다 (GRDB는 패키지가 가져옴).
- 번들 ID `com.temzzang.MusicTagManager`, 아이콘, `fpcalc`(Resources/bin, 복사 시 서명), Apple Events 권한, ad-hoc 서명은 `scripts/build_app.sh`와 같다.
- 스킴 목록의 `MusicTagManager`·`MTMCore`는 패키지가 만든 것이다. 앱은 **MusicTag Manager**(띄어쓰기) 스킴을 쓴다.
- 단위 테스트는 패키지 테스트라 `swift test`로 실행하거나, `Package.swift`를 Xcode로 열어 ⌘U.
- 프로젝트 설정을 바꿨으면 `python3 scripts/generate_xcodeproj.py`로 다시 만들 수 있다.

Xcode에서 실행하면 서명이 바뀌어 Music 제어 권한을 다시 물을 수 있다 (ad-hoc 서명).

| 모듈 | 내용 |
|---|---|
| `MTMCore/Library` | ITLibrary 읽기, 플레이리스트 범위, 완비 판정 |
| `MTMCore/Scan` | 증분 검사 (수정 시각이 같은 곡은 저장값 재사용) |
| `MTMCore/Identification` | MusicBrainz·iTunes·AcoustID, 앨범 단위 결정, 신뢰도 |
| `MTMCore/Apply` | 쓰기 정책, 커버, 스냅샷 → 쓰기 → 검증, 되돌리기 |
| `MTMCore/Export` | CSV 검수표 |
| `MusicTagManager` | SwiftUI 앱 (온보딩·대시보드·검토 대기함·설정, 다크/기본 테마) |

## 데이터 위치

- DB: `~/Library/Application Support/MusicTagManager/mtm.sqlite` (선택·검사 결과·제안·작업·스냅샷·커버 확인·API 캐시)
- 커버: `.../Artwork` · 직접 지정한 커버: `.../Artwork/User` · 되돌리기 스냅샷·백업: `.../Backup`(보존 기간 지나면 자동 정리)
- 로그: 콘솔 앱에서 subsystem `com.temzzang.MusicTagManager`

## 서드파티

- `Resources/bin/fpcalc`: Chromaprint 1.6.1 공식 macOS arm64 단독 바이너리 (LGPL 2.1, https://acoustid.org/chromaprint)
- GRDB.swift (MIT)
- Sparkle (MIT) — 자동 업데이트 (배포 빌드에만 임베드, EdDSA 서명으로 검증)

## 알려진 제약

- iTunes Search `country=KR`은 음원을 돌려주지 않아 US 스토어를 쓴다(한국 곡은 영문 표기 → 커버·교차 확인용). 한글 표기는 MusicBrainz 기준.
- MusicBrainz·iTunes·Cover Art Archive에 없는 국내 컴필레이션·OST는 곡은 식별돼도 커버를 못 찾을 수 있다 → 직접 수정에서 이미지를 지정한다.
- Cover Art Archive 커버는 400~500px가 많다. 600px 이상이 없으면 300px 이상도 쓴다(설정에서 끌 수 있음).
- ITLibrary의 `hasArtworkAvailable`은 커버를 지운 뒤에도 true로 남는다 → `artwork` 객체까지 확인하고, 쓰기 검증은 AppleScript로 한다.
- AppleScript는 메인 스레드에서만 동작한다(백그라운드 스레드에서는 Music 응답을 받지 못해 멈춤). 곡 단위로 짧게 실행해 UI 정지를 줄인다.
- Music은 트랙 수를 트랙 번호보다 작게 쓰면 조용히 무시한다 → 이런 값은 쓰지 않는다.
- 첫 식별은 외부 API 제한 때문에 오래 걸린다(곡당 약 1~2초, 정리 대상 4천여 곡이면 1~2시간). 두 번째부터는 캐시로 빠르다.
- XLSX 대신 CSV만 지원한다. Music 보관함 밖 파일의 태그 직접 쓰기는 지원하지 않는다.
# MusicTagManager
