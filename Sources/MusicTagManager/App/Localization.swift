import Foundation
import Observation

/// 앱 언어. 나중에 다른 언어를 추가할 수 있다 (여기에 case를 더하고 테이블에 문자열을 추가).
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, english, korean
    var id: String { rawValue }

    /// 피커에 보여 줄 이름
    var displayName: String {
        switch self {
        case .system: return L("language.system")
        case .english: return "English"
        case .korean: return "한국어"
        }
    }

    /// 날짜·숫자 포맷에 쓸 로케일 (명시 선택은 해당 언어, system은 맥 지역 설정 유지)
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .korean: return Locale(identifier: "ko_KR")
        case .system: return .autoupdatingCurrent
        }
    }

    /// 실제 적용할 언어 (system은 맥 설정에 따름: 한국어면 한국어, 그 외 영어)
    var resolved: ResolvedLanguage {
        switch self {
        case .english: return .english
        case .korean: return .korean
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ko") ? .korean : .english
        }
    }
}

enum ResolvedLanguage { case english, korean }

/// 현재 언어를 보관하는 관찰 가능한 전역 객체. 뷰 body에서 `L(...)`로 문자열을 읽으면
/// 언어가 바뀔 때 SwiftUI가 자동으로 다시 그린다 (Observation 추적).
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()
    var language: AppLanguage = .system
    private init() {}

    func string(_ key: String) -> String {
        guard let entry = L10nTable.entries[key] else {
            assertionFailure("Missing localization key: \(key)")
            return key
        }
        switch language.resolved {
        case .korean: return entry.ko
        case .english: return entry.en
        }
    }
}

/// 지역화 문자열. 뷰 body 안에서 호출해야 언어 변경 시 자동 갱신된다.
func L(_ key: String) -> String { LocalizationManager.shared.string(key) }

/// Sparkle 업데이트 대화상자처럼 **시스템·프레임워크가 제공하는 UI**가 앱에서 고른 언어를 따르도록
/// 프로세스의 `AppleLanguages` 우선순위를 맞춘다. (앱 자체 UI 문구는 `LocalizationManager`가 담당)
/// 명시 선택(영어·한국어)만 강제하고, '시스템'은 맥 설정을 그대로 쓰도록 재정의를 지운다.
/// 이미 로드된 번들은 로케일을 캐시하므로, 실행 중 전환은 다음 실행부터 Sparkle UI에 반영된다.
func syncSystemUILanguage(_ language: AppLanguage) {
    let key = "AppleLanguages"
    switch language {
    case .system: UserDefaults.standard.removeObject(forKey: key)
    case .english: UserDefaults.standard.set(["en"], forKey: key)
    case .korean: UserDefaults.standard.set(["ko"], forKey: key)
    }
}

/// 현재 앱 언어의 로케일 (날짜·숫자 포맷용). 뷰 body에서 쓰면 언어 변경 시 갱신된다.
var appLocale: Locale { LocalizationManager.shared.language.locale }

/// 신뢰도 근거 토큰(DB에 한국어로 저장됨, 예: "제목 일치 +20")을 현재 언어로 바꾼다.
/// 라벨 뒤의 점수(" +20"·" -30")는 그대로 둔다. 매칭 안 되면 원문 그대로.
func localizeEvidenceReason(_ raw: String) -> String {
    let map: [(ko: String, key: String)] = [
        ("오디오 지문 일치", "scorer.fingerprint"),
        ("같은 앨범 곡의 지문 확인", "scorer.albumFingerprint"),
        ("제목 일치", "scorer.titleExact"),
        ("제목 유사", "scorer.titleClose"),
        ("가수 일치", "scorer.artistExact"),
        ("가수 유사", "scorer.artistClose"),
        ("앨범명 일치", "scorer.albumExact"),
        ("길이 차이 3초 이내", "scorer.duration"),
        ("앨범 트랙 수 일치", "scorer.trackCount"),
        ("2개 이상 소스 일치", "scorer.sourcesAgree"),
        ("비슷한 후보가 여럿", "scorer.ambiguous"),
        ("기존 제목·가수와 불일치", "scorer.coreMismatch"),
        ("가수가 다른 사람으로 바뀜 → 자동 적용 안 함", "scorer.artistReplaced"),
        ("입력한 정보로 다시 식별", "reason.reidentifiedWithInput"),
        ("후보 없음", "reason.noCandidate"),
    ]
    for (ko, key) in map where raw == ko || raw.hasPrefix(ko + " ") {
        return L(key) + raw.dropFirst(ko.count)
    }
    // 식별 실패 사유(인자가 들어간 긴 문장)는 템플릿 역매칭으로 현재 언어로 바꾼다
    return localizeResolverReason(raw)
}

/// 식별 실패 사유를 현재 언어로 바꾼다. 이 문장들은 식별 시점 언어로 **포맷되어 DB에 저장**되므로
/// (예: 한국어로 식별한 뒤 영어로 전환), 저장된 문장을 한국어·영어 템플릿 양쪽으로 역매칭해 인자를
/// 뽑아내고 현재 언어 템플릿에 다시 채운다. 매칭 안 되면 원문 그대로.
func localizeResolverReason(_ raw: String) -> String {
    let lang = LocalizationManager.shared.language.resolved

    // 단독 사유: 테이블에서 ko/en 템플릿을 가져온다
    let keys = ["resolve.noAlbumName", "resolve.noTitle", "resolve.noAcoustID",
                "resolve.fp.drm", "resolve.fp.cloud", "resolve.fp.noLocation",
                "resolve.fp.noMatch", "resolve.fp.fileMissing", "resolve.artistNotFound",
                "resolve.noAlbumForRecording", "resolve.itunesNoMatch"]
    var templates: [(ko: String, en: String)] = keys.compactMap {
        L10nTable.entries[$0].map { ($0.ko, $0.en) }
    }
    // 복합 검색 사유: resolver가 조각(검색어·접미사·대상·건수)을 이어 붙여 하나의 문장으로 저장한다.
    // 통짜 템플릿으로 역매칭한다 (AlbumResolver.resolveViaMusicBrainz의 조립과 1:1 대응).
    templates.append(contentsOf: [
        (ko: "MusicBrainz 검색 ‘%@’ · %@: 결과 없음",
         en: "MusicBrainz search “%@” · %@: no results"),
        (ko: "MusicBrainz 검색 ‘%@’ (가수 모름 → 제목+길이): 결과 없음",
         en: "MusicBrainz search “%@” (artist unknown → title+length): no results"),
        (ko: "MusicBrainz 검색 ‘%@’ · %@: 결과 %d건 중 제목·가수가 맞는 곡 없음 (예: %@ — %@)",
         en: "MusicBrainz search “%@” · %@: no track matching title·artist among %d results (e.g., %@ — %@)"),
        (ko: "MusicBrainz 검색 ‘%@’ (가수 모름 → 제목+길이): 결과 %d건 중 제목·길이(±3초)가 맞는 곡 없음 (예: %@ — %@)",
         en: "MusicBrainz search “%@” (artist unknown → title+length): no track matching title·length (±3s) among %d results (e.g., %@ — %@)"),
    ])

    for t in templates {
        for source in [t.ko, t.en] {
            if let args = matchReasonTemplate(raw, source) {
                return formatReasonTemplate(lang == .korean ? t.ko : t.en, args)
            }
        }
    }
    return raw
}

/// 템플릿의 `%@`·`%d` 지정자 (순차)
private let reasonSpecRegex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@d]")

/// `template`(지정자 포함)을 정규식으로 바꿔 `raw`에서 인자들을 순서대로 뽑는다. 안 맞으면 nil.
private func matchReasonTemplate(_ raw: String, _ template: String) -> [String]? {
    var pattern = "^"
    var last = template.startIndex
    let full = NSRange(template.startIndex..., in: template)
    for m in reasonSpecRegex.matches(in: template, range: full) {
        guard let r = Range(m.range, in: template) else { continue }
        pattern += NSRegularExpression.escapedPattern(for: String(template[last..<r.lowerBound]))
        pattern += template[r].hasSuffix("d") ? "(\\d+)" : "(.+?)"
        last = r.upperBound
    }
    pattern += NSRegularExpression.escapedPattern(for: String(template[last...])) + "$"
    guard let rx = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
          let match = rx.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
    var args: [String] = []
    for i in 1..<match.numberOfRanges {
        guard let r = Range(match.range(at: i), in: raw) else { return nil }
        args.append(String(raw[r]))
    }
    return args
}

/// 뽑아낸 인자들을 현재 언어 `template`에 순서대로 채운다 (`%d`는 정수로 변환).
private func formatReasonTemplate(_ template: String, _ args: [String]) -> String {
    var cvargs: [CVarArg] = []
    let full = NSRange(template.startIndex..., in: template)
    for (i, m) in reasonSpecRegex.matches(in: template, range: full).enumerated() where i < args.count {
        guard let r = Range(m.range, in: template) else { continue }
        cvargs.append(template[r].hasSuffix("d") ? (Int(args[i]) ?? 0) : args[i])
    }
    return String(format: template, arguments: cvargs)
}

/// 포맷 인자가 있는 지역화 문자열 (예: "%@개").
func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: LocalizationManager.shared.string(key), arguments: args)
}

/// 영어/한국어 문자열 테이블. 화면을 번역할 때마다 항목을 추가한다.
enum L10nTable {
    struct Entry {
        let en: String
        let ko: String
        init(_ en: String, _ ko: String) { self.en = en; self.ko = ko }
    }

    static let entries: [String: Entry] = [
        // 공통
        "common.cancel": Entry("Cancel", "취소"),
        "common.save": Entry("Save", "저장"),
        "common.add": Entry("Add", "추가"),
        "common.revert": Entry("Revert", "되돌리기"),
        "common.defaults": Entry("Reset to defaults", "기본값으로"),
        "common.applyRescan": Entry("Apply & Rescan", "적용하고 다시 검사"),

        // 언어
        "language.system": Entry("System default", "시스템 기본"),

        // 테마
        "theme.system": Entry("System", "시스템 설정"),
        "theme.light": Entry("Light", "기본"),
        "theme.dark": Entry("Dark", "다크"),

        // 설정 탭
        "settings.tab.playlists": Entry("Playlists", "플레이리스트"),
        "settings.tab.rules": Entry("Rules", "판정 규칙"),
        "settings.tab.identify": Entry("Identification", "식별"),
        "settings.tab.writePolicy": Entry("Write Rules", "쓰기 정책"),
        "settings.tab.general": Entry("General", "일반"),

        // 플레이리스트 탭
        "settings.playlist.confirmTitle": Entry("Change playlists?", "플레이리스트를 바꿀까요?"),
        "settings.playlist.confirmChange": Entry("Change & Reset", "바꾸고 초기화"),

        // 판정 규칙 탭
        "settings.rules.placeholdersAsEmpty": Entry("Treat placeholder values as empty", "플레이스홀더 값을 빈 값으로 간주"),
        "settings.rules.filenameAsEmpty": Entry("Treat filename-like titles (“Artist - Title”, “05 Title”) as empty",
                                                "파일명 형태의 제목(‘아티스트 - 제목’, ‘05 제목’)을 빈 값으로 간주"),
        "settings.rules.filenameNote": Entry("Filename-like titles count as empty only when the artist or album is also empty. Because Music fills the title from the filename, a title matching the filename alone isn’t treated as missing.",
                                             "파일명 형태의 제목은 가수명이나 앨범명도 비어 있을 때만 빈 값으로 봅니다. Music이 파일명을 제목으로 바꿔 두기 때문에, 제목이 파일명과 같다는 것만으로는 판단하지 않습니다."),
        "settings.rules.artistPlaceholders": Entry("Artist name placeholders", "가수명 플레이스홀더"),
        "settings.rules.albumPlaceholders": Entry("Album name placeholders", "앨범명 플레이스홀더"),
        "settings.rules.titlePatterns": Entry("Track title placeholders (regex)", "곡 제목 플레이스홀더 (정규식)"),

        // 식별 탭
        "settings.id.sources": Entry("Identification sources", "식별 소스"),
        "settings.id.musicbrainzAlways": Entry("Always on (1/sec)", "항상 사용 (초당 1회)"),
        "settings.id.useITunes": Entry("iTunes Search (artwork · cross-check)", "iTunes Search (커버·교차 확인)"),
        "settings.id.useAcoustID": Entry("AcoustID audio fingerprint", "AcoustID 오디오 지문"),
        "settings.id.apiKeyField": Entry("AcoustID API key", "AcoustID API 키"),
        "settings.id.keySaved": Entry("Using your key (saved in Keychain)", "내 키 사용 중 (키체인에 저장됨)"),
        "settings.id.keyNone": Entry("Using the built-in shared key — enter your own to override (optional)", "내장 공용 키 사용 중 — 원하면 내 키를 넣어 바꿀 수 있습니다 (선택)"),
        "settings.id.deleteKey": Entry("Delete key", "키 삭제"),
        "settings.id.acoustidFooter": Entry("A shared key is built in, so fingerprinting works out of the box. For heavy use you can register your own free key at acoustid.org/new-application.", "공용 키가 내장돼 있어 바로 지문 식별이 동작합니다. 많이 쓰실 경우 acoustid.org/new-application 에서 무료 키를 발급해 넣을 수 있습니다."),
        "settings.id.display": Entry("Display", "표기"),
        "settings.id.preferKorean": Entry("Prefer Korean names for Korean artists", "한국 가수 이름은 한글 표기 우선"),
        "settings.id.mbContact": Entry("MusicBrainz contact (email)", "MusicBrainz 연락처 (이메일)"),
        "settings.id.mbContactNote": Entry("Sent with the app name on every request, per MusicBrainz rules.", "MusicBrainz 이용 규칙에 따라 요청마다 앱 이름과 함께 보냅니다."),
        "settings.id.keyDeleted": Entry("Key deleted", "키를 삭제했습니다"),
        "settings.id.keySavedMsg": Entry("Saved", "저장했습니다"),
        "settings.id.saveFailed": Entry("Couldn’t save: %@", "저장하지 못했습니다: %@"),

        // 쓰기 정책 탭
        "settings.write.footer": Entry("Default: Title, Artist, and Album use “Replace if different”; the rest use “Only if empty.” Tracks whose identified title/artist differ fundamentally (likely a different song) are only filled in, not replaced.",
                                       "기본값: 곡 제목·가수명·앨범명은 ‘다르면 교체’, 나머지는 ‘비어 있을 때만’. 식별 결과가 기존 제목·가수와 핵심적으로 다른 곡(다른 곡일 가능성)은 교체하지 않고 빈 칸만 채웁니다."),
        "settings.write.warning": Entry("“Replace if different” overwrites values you already have with the identified result. The previous values are kept as a snapshot you can undo.",
                                        "‘다르면 교체’는 이미 입력된 값을 식별 결과로 덮어씁니다. 바꾸기 전 값은 스냅샷으로 남아 되돌릴 수 있습니다."),
        "settings.write.allDefaults": Entry("Reset all to defaults", "모두 기본값으로"),
        "settings.write.allFillEmpty": Entry("Set all to “Only if empty”", "모두 ‘비어 있을 때만’으로"),

        // 일반 탭
        "settings.general.display": Entry("Appearance", "화면"),
        "settings.general.theme": Entry("Theme", "테마"),
        "settings.general.language": Entry("Language", "언어"),
        "settings.general.applySection": Entry("Applying", "적용"),
        "settings.general.completionAlert": Entry("Show a summary when applying finishes", "적용이 끝나면 결과 알림 표시"),
        "settings.general.allowLowRes": Entry("If no high-resolution (600px) artwork exists, use low-resolution (≥300px) artwork too",
                                              "고해상도(600px) 커버가 없으면 저해상도(300px 이상) 커버도 사용"),
        "settings.general.lowResNote": Entry("Cover Art Archive artwork is often 400–500px. When off, artwork under 600px isn’t added.",
                                             "Cover Art Archive 커버는 400~500px인 경우가 많습니다. 끄면 600px 미만 커버는 넣지 않습니다."),
        "settings.general.safety": Entry("Safety", "안전"),
        "settings.general.writeGuard": Entry("Safety: don’t write to libraries with more than %@ tracks", "안전장치: 곡이 %@개를 넘는 보관함에는 쓰지 않기"),
        "settings.general.writeGuardNote": Entry("Protects your main library while you verify apply/undo on a test library. Turn it off when you’re done.",
                                                 "테스트 보관함에서 적용·되돌리기를 확인하는 동안 메인 보관함을 보호합니다. 확인이 끝나면 끄세요."),
        "settings.general.fullBackup": Entry("Back up the whole original file before writing", "쓰기 전에 원본 음악 파일 전체 백업"),
        "settings.general.fullBackupNote": Entry("Off by default: a snapshot of tags/artwork before changes is enough to undo. When on, original files are copied to Backup/Files in the data folder (APFS clone uses space only for changes). Current backup size: %@",
                                                 "기본은 꺼짐: 바꾸기 전 태그·커버를 스냅샷으로 남겨 되돌리기에는 충분합니다. 켜면 원본 파일을 데이터 폴더의 Backup/Files에 복사합니다(APFS 복제라 바뀐 부분만큼만 용량을 씀). 현재 백업 용량: %@"),
        "settings.general.help": Entry("Help", "도움말"),
        "settings.general.onboarding": Entry("Getting started guide", "시작 가이드"),
        "settings.general.showOnboarding": Entry("Show again", "다시 보기"),
        "settings.general.updates": Entry("Updates", "업데이트"),
        "update.check": Entry("Check for Updates…", "업데이트 확인…"),
        "settings.general.snapshotRetention": Entry("Keep undo snapshots for", "되돌리기 스냅샷 보관"),
        "settings.general.snapshotRetentionNote": Entry("Snapshots older than this (and their backup files) are cleaned up automatically. Jobs past this period can no longer be undone.", "이 기간이 지난 스냅샷과 백업 파일은 자동으로 정리됩니다. 기간이 지난 작업은 더 이상 되돌릴 수 없습니다."),
        "retention.7": Entry("7 days", "7일"),
        "retention.30": Entry("30 days", "30일"),
        "retention.90": Entry("90 days", "90일"),
        "retention.365": Entry("1 year", "1년"),
        "retention.forever": Entry("Forever", "무제한"),
        "settings.general.data": Entry("Data", "데이터"),
        "settings.general.dataFolder": Entry("Data folder", "데이터 폴더"),
        "settings.general.showInFinder": Entry("Show in Finder", "Finder에서 보기"),

        // 공통 (추가)
        "common.ok": Entry("OK", "확인"),
        "common.apply": Entry("Apply", "적용"),
        "common.remove": Entry("Remove", "빼기"),
        "common.directEdit": Entry("Edit", "직접 수정"),
        "common.directEditEllipsis": Entry("Edit…", "직접 수정…"),
        "count.songs": Entry("%d songs", "%d곡"),

        // MTMCore 필드 레이블
        "field.title": Entry("Title", "곡 제목"),
        "field.artist": Entry("Artist", "가수명"),
        "field.album": Entry("Album", "앨범명"),
        "field.albumArtist": Entry("Album Artist", "앨범 아티스트"),
        "field.genre": Entry("Genre", "장르"),
        "field.year": Entry("Year", "연도"),
        "field.trackNumber": Entry("Track No.", "트랙 번호"),
        "field.trackCount": Entry("Track Count", "트랙 수"),
        "field.discNumber": Entry("Disc No.", "디스크 번호"),
        "field.discCount": Entry("Disc Count", "디스크 수"),
        "field.artwork": Entry("Artwork", "앨범커버"),

        // 신뢰도
        "level.high": Entry("High", "높음"),
        "level.medium": Entry("Medium", "보통"),
        "level.low": Entry("Low", "낮음"),
        "level.none": Entry("Not identified", "식별 실패"),

        // 완비 상태
        "completeness.complete": Entry("Complete", "완비"),
        "completeness.incomplete": Entry("Target", "정리 대상"),
        "completeness.excludedCloud": Entry("Cloud only", "클라우드 전용"),
        "completeness.excludedMissingFile": Entry("File missing", "파일 없음"),
        "completeness.excludedUnsupported": Entry("Not music", "음악 아님"),

        // 쓰기 정책
        "writePolicy.fillEmpty": Entry("Only if empty", "비어 있을 때만"),
        "writePolicy.replaceIfDifferent": Entry("Replace if different", "다르면 교체"),
        "writePolicy.never": Entry("Never", "변경 안 함"),

        // 처리 상태
        "status.applied": Entry("Applied", "적용 완료"),
        "status.failed": Entry("Failed", "적용 실패"),
        "status.pending": Entry("Pending", "검토 대기"),
        "status.override": Entry("Edited", "직접 수정"),
        "status.unidentified": Entry("Not identified", "식별 실패"),
        "status.nothingToChange": Entry("Keep", "바꿀 값 없음"),
        "status.rejected": Entry("Rejected", "거절"),

        // 탭 / 필터
        "tab.tracks": Entry("Tracks", "곡 목록"),
        "tab.proposals": Entry("Results", "식별 결과"),
        "tab.review": Entry("Review", "검토 대기함"),
        "tab.history": Entry("History", "작업 이력"),
        "filter.all": Entry("All", "전체"),
        "filter.excluded": Entry("Excluded", "수정 불가"),

        // 대시보드
        "dash.scanning": Entry("Scanning the selected playlists…", "선택한 플레이리스트를 검사하는 중…"),
        "dash.noScan.title": Entry("No scan results yet", "아직 검사 결과가 없습니다"),
        "dash.noScan.desc": Entry("Press “Rescan.”", "‘다시 검사’를 누르세요."),
        "dash.removePlaylist.title": Entry("Remove “%@” from the scope?", "‘%@’을(를) 대상에서 뺄까요?"),
        "dash.removePlaylist.msg": Entry("Rescans with the remaining playlists.", "남은 플레이리스트로 다시 검사합니다."),
        "dash.fp.selectFirst": Entry("Select tracks to re-identify in the Complete list first.", "완비 목록에서 재식별할 곡을 먼저 선택하세요."),
        "dash.fp.noneFound": Entry("No fingerprint results differing from the current tags were found for the selected tracks.", "선택한 곡에서 현재 태그와 다른 오디오 지문 결과를 찾지 못했습니다."),
        "dash.scope": Entry("Scope", "대상"),
        "dash.changePlaylists": Entry("Change playlists", "플레이리스트 변경"),
        "dash.rescanAll": Entry("Rescan everything", "전체 다시 검사"),
        "dash.rescan": Entry("Rescan", "다시 검사"),
        "dash.rescan.help": Entry("Rescans only changed tracks. Choose a full rescan from the menu.", "바뀐 곡만 다시 검사합니다. 메뉴에서 전체 다시 검사를 고를 수 있습니다."),
        "dash.scannedAt": Entry("Scanned %@", "%@ 검사"),
        "dash.wholeLibrary": Entry("Whole library", "전체 라이브러리"),
        "dash.removeFromScope": Entry("Remove from scope", "대상에서 빼기"),
        "dash.identifyResults": Entry("Results", "식별 결과"),
        "dash.searchPlaceholder": Entry("Search title · artist · album", "제목·가수·앨범 검색"),
        "dash.missingFilter": Entry("No %1$@ ✕", "%1$@ 없음 ✕"),
        "dash.directEdit.help": Entry("Edit the selected track’s tags/artwork directly. (You can also double-click a row.)", "선택한 곡의 태그·커버를 직접 고칩니다. (목록에서 곡을 더블클릭해도 됩니다)"),
        "dash.fpSearch": Entry("Fingerprint search", "오디오지문 검색"),
        "dash.fpSearch.help": Entry("Re-identify the selected Complete tracks by audio fingerprint to review results that differ from current tags.", "선택한 완비 곡을 오디오 지문으로 다시 식별해, 현재 태그와 다른 결과를 확인·수정합니다."),
        "dash.showingCount": Entry("Showing %d tracks", "%d곡 표시"),
        "dash.reviewOnly": Entry("Pending only", "검토대기 보기"),
        "dash.reviewOnly.help": Entry("When on, shows only tracks with the “Pending review” status.", "켜면 상태가 ‘검토 대기’인 곡만 보여 줍니다"),
        "dash.applySelected": Entry("Apply selected", "선택 적용"),
        "dash.proposalFooter": Entry("Showing %d tracks · Music library isn’t changed until you apply", "%d곡 표시 · 적용하기 전까지 Music 보관함은 바뀌지 않습니다"),
        "dash.reviewSheet": Entry("Review sheet", "검수표"),
        "dash.exportCSV": Entry("Export CSV…", "CSV로 내보내기…"),
        "dash.importCSV": Entry("Import CSV…", "CSV 가져오기…"),
        "dash.reviewSheet.help": Entry("Review results in Excel/Numbers and import back (Decision column: Approve/Reject; proposed values editable).", "식별 결과를 엑셀·Numbers에서 검수하고 다시 가져옵니다 (결정 열: 승인/거절, 제안값 수정 가능)"),
        "dash.doubleClickHint": Entry("You can also double-click a row", "행을 더블클릭해도 됩니다"),
        "dash.applySelectedN": Entry("Apply selected (%d)", "선택 적용 (%d곡)"),
        "dash.applyAllN": Entry("Apply all (%d)", "전체 적용 (%d곡)"),
        "dash.applyAll.help": Entry("Applies every track with changes in the list shown now (confidence filter · search applied).", "지금 표시된 목록(신뢰도 필터·검색 적용) 중 바뀔 값이 있는 곡을 모두 적용합니다"),
        "dash.applyAllConfirm": Entry("Apply all", "전체 적용"),
        "dash.confirmApplyAll.title": Entry("Apply to %d tracks shown?", "표시된 목록의 %d곡에 적용할까요?"),
        "dash.confirmApplyAll.msgFiltered": Entry("Applies only tracks with changes among those shown%@. You can undo anytime from History.", "%@표시된 곡 중 ‘적용 시 변경’이 있는 곡만 적용합니다. 작업 이력에서 언제든 되돌릴 수 있습니다."),
        "dash.confirmApplyAll.filterPrefix": Entry(" (filter: %@)", "‘%@’ 필터에 "),
        "dash.confirmApply.title": Entry("Apply to %d selected tracks?", "선택한 %d곡에 적용할까요?"),
        "dash.confirmApply.msg": Entry("Writes only items in “Changes on apply” (per your write rules). Each track’s prior state is saved, then written to Music and re-read to verify; you can undo anytime from History.", "‘적용 시 변경’에 표시된 항목만 씁니다(설정의 쓰기 정책 기준). 곡마다 변경 전 상태를 저장한 뒤 Music에 쓰고 다시 읽어 확인하며, 작업 이력에서 언제든 되돌릴 수 있습니다."),
        "dash.exportFilename": Entry("MusicTag review sheet %@.csv", "MusicTag 검수표 %@.csv"),
        "dash.referenceValue": Entry("Ref: %@", "참고: %@"),
        "dash.reference.help": Entry("Keeps the existing value (per write rules). Shown as a reference that another value was proposed.", "기존 값을 유지합니다 (쓰기 정책). 다른 값이 제안되었다는 참고 정보입니다."),

        // 컬럼 헤더
        "col.title": Entry("Title", "제목"),
        "col.artist": Entry("Artist", "가수"),
        "col.album": Entry("Album", "앨범"),
        "col.status": Entry("Status", "상태"),
        "col.file": Entry("File", "파일"),
        "col.missing": Entry("Missing", "누락 항목"),
        "col.confidence": Entry("Confidence", "신뢰도"),
        "col.current": Entry("Current (Title · Artist · Album)", "현재 (제목 · 가수 · 앨범)"),
        "col.propTitle": Entry("Proposed title", "제안 제목"),
        "col.propArtist": Entry("Proposed artist", "제안 가수"),
        "col.propAlbum": Entry("Proposed album", "제안 앨범"),
        "col.cover": Entry("Artwork", "커버"),
        "col.writes": Entry("Changes on apply", "적용 시 변경"),
        "col.reasons": Entry("Reasons", "근거"),

        // 카드
        "card.scope.title": Entry("Tracks in scope", "대상 곡"),
        "card.complete.ring": Entry("Complete", "완비"),
        "card.applied": Entry("Applied", "수정 완료"),
        "card.applied.help": Entry("Tracks this app applied info to (History)", "이 앱에서 정보를 적용한 곡 (작업 이력)"),
        "card.duplicates": Entry("Counting %d duplicates across playlists once", "여러 플레이리스트에 중복된 %d건은 한 번만 셉니다"),
        "card.missing.title": Entry("Missing items", "누락 항목"),
        "card.applyStatus.title": Entry("Apply status", "적용 현황"),
        "card.bar.applied": Entry("Applied", "수정 완료"),
        "card.bar.pending": Entry("Pending", "검토 대기"),
        "card.bar.failed": Entry("Apply failed", "적용 실패"),
        "card.bar.unidentified": Entry("Not identified", "식별 실패"),

        // 식별 실행 버튼
        "dash.runIdentify": Entry("Identify", "식별 실행"),
        "dash.runIdentify.help": Entry("Identify tracks that need work via MusicBrainz · iTunes · AcoustID to build proposals. Your library isn’t changed yet.", "정리 대상 곡을 MusicBrainz·iTunes·AcoustID로 식별해 제안값을 만듭니다. 보관함은 아직 수정하지 않습니다."),
        "dash.reidentifyAll": Entry("Re-identify already-identified tracks too", "이미 식별한 곡도 다시 식별"),

        // 상태 셀 팝오버
        "dash.failed.hint": Entry("You can review and apply this track’s values and artwork in “Edit.”", "이 곡은 ‘직접 수정’에서 값과 커버를 직접 확인해 적용할 수 있습니다."),
        "dash.editToApply": Entry("Apply via Edit…", "직접 수정에서 적용…"),
        "dash.unidentified.hint": Entry("Enter the title/artist/album yourself to re-identify just this track.", "제목·가수·앨범을 직접 입력해 이 곡만 다시 식별할 수 있습니다."),
        "dash.enterToReidentify": Entry("Enter info and re-identify…", "직접 입력해서 다시 식별…"),

        // 플레이리스트 변경 시트
        "sheet.scopePlaylists": Entry("Scope playlists", "대상 플레이리스트"),
        "sheet.resetMessage": Entry("History, applied count, and identification results are reset. Changes applied earlier can no longer be undone in this app. (The original-file backup folder is kept.)", "작업 이력, 정리 완료 수, 식별 결과가 초기화됩니다. 이전에 적용한 변경은 더 이상 이 앱에서 되돌릴 수 없습니다. (원본 파일 백업 폴더는 그대로 남습니다)"),

        // 오디오 지문 검색 시트
        "fp.title": Entry("Fingerprint search results", "오디오 지문 검색 결과"),
        "fp.desc": Entry("Found %d tracks differing from current tags. Check one and “Edit now” to review/fix it in the Edit screen, or check several and “Move to results” to review/apply them in the Review queue. (Your library isn’t changed yet.)", "현재 태그와 다른 결과 %d곡을 찾았습니다. 한 곡을 체크하고 ‘바로 수정’하면 직접 수정 화면에서 값을 확인해 고칠 수 있고, 여러 곡을 체크해 ‘식별 결과로 이동’하면 검토 대기 목록에서 확인·적용할 수 있습니다. (보관함은 아직 바꾸지 않습니다)"),
        "fp.colCurrent": Entry("Current (Title · Artist · Album)", "현재 (제목 · 가수 · 앨범)"),
        "fp.colResult": Entry("Fingerprint result (Title · Artist · Album)", "지문 결과 (제목 · 가수 · 앨범)"),
        "fp.selectAll": Entry("Select all", "전체 선택"),
        "fp.deselectAll": Entry("Deselect all", "전체 해제"),
        "fp.editNow": Entry("Edit now", "바로 수정"),
        "fp.editNow.help": Entry("Edit the one selected track directly in the Edit screen", "선택한 한 곡을 직접 수정 화면에서 바로 고칩니다"),
        "fp.moveToResults": Entry("Move to results (%d)", "식별 결과로 이동 (%d)"),

        // 공통 (추가)
        "common.close": Entry("Close", "닫기"),
        "common.none": Entry("none", "없음"),
        "common.approve": Entry("Approve", "승인"),
        "common.reject": Entry("Reject", "거절"),
        "common.detail": Entry("Details", "자세히"),

        // 검토 대기함
        "review.chip.pending": Entry("Pending", "검토 대기"),
        "review.chip.albums": Entry("Albums", "앨범"),
        "review.showAll": Entry("Show all", "전체 보기"),
        "review.showAll.help": Entry("When on, also shows low-confidence and unidentified tracks. When off, only High/Medium and apply-failed tracks.", "켜면 신뢰도가 낮은 곡과 식별 실패 곡도 함께 보여 줍니다. 끄면 높음·보통 곡과 적용 실패 곡만 보입니다."),
        "review.approveHighMedium": Entry("Approve all High/Medium", "높음·보통 전부 승인"),
        "review.approveSelected": Entry("Approve selected", "선택 승인"),
        "review.rejectAll": Entry("Reject all", "모두 거절"),
        "review.applyAllN": Entry("Apply all (%d)", "전체 적용 (%d곡)"),
        "review.applyAll.help": Entry("Applies the “Changes on apply” values to every track in the review queue (any confidence).", "검토 대기함의 모든 곡(신뢰도 무관)에 ‘적용 시 변경’ 값을 적용합니다"),
        "review.keyHints": Entry("↑↓ move · Return/double-click details · ⌘Return approve · Delete reject", "↑↓ 이동 · Return/더블클릭 자세히 · ⌘Return 승인 · Delete 거절"),
        "review.empty.title": Entry("No tracks to review", "검토할 곡이 없습니다"),
        "review.empty.desc": Entry("Tracks awaiting apply and tracks that failed to apply collect here.", "식별 결과 중 적용을 기다리는 곡과 적용에 실패한 곡이 여기에 모입니다."),
        "review.confirmAll.title": Entry("Apply to all %d tracks in the review queue?", "검토 대기함의 %d곡에 모두 적용할까요?"),
        "review.confirmAll.msg": Entry("Low-confidence tracks are included. Each track’s prior state is saved before writing, and you can undo anytime from History.", "신뢰도가 낮은 곡도 포함됩니다. 곡마다 변경 전 상태를 저장한 뒤 쓰며, 작업 이력에서 언제든 되돌릴 수 있습니다."),
        "review.confirmReject.title": Entry("Reject all tracks in the review queue?", "검토 대기 중인 곡을 모두 거절할까요?"),
        "review.confirmReject.confirm": Entry("Reject all", "모두 거절"),
        "review.confirmReject.msg": Entry("Nothing is written to Music. Re-running identification brings them back to the review queue.", "Music에는 아무것도 쓰지 않습니다. 식별을 다시 실행하면 검토 대기로 돌아옵니다."),
        "review.failCount": Entry("Apply failed %d", "적용 실패 %d"),
        "review.tracksAndChanges": Entry("%1$d tracks · Changes: %2$@", "%1$d곡 · 바뀔 항목: %2$@"),
        "review.dropHelp": Entry("Drop an image to set it as the artwork for this album’s tracks without artwork", "이미지를 끌어 놓으면 이 앨범의 커버 없는 곡에 커버로 지정합니다"),

        // 커버 썸네일 placeholder
        "art.noCover": Entry("No artwork", "커버 없음"),
        "art.noCandidate": Entry("No candidate", "후보 없음"),
        "art.keep": Entry("Keep", "유지"),
        "art.currentNone": Entry("Current\nno artwork", "현재\n커버 없음"),
        "art.dropHere": Entry("Drop an\nimage here", "이미지를\n끌어 놓기"),

        // 앨범 상세
        "albumDetail.hint": Entry("Only cells that change from the current value are shown in bold. Double-click a row to edit directly.", "현재 값과 다르게 바뀌는 칸만 진하게 표시됩니다. 행을 더블클릭하면 직접 수정할 수 있습니다."),
        "albumDetail.rejectAlbum": Entry("Reject this album", "이 앨범 거절"),
        "albumDetail.approveAlbum": Entry("Approve this album", "이 앨범 승인"),
        "col.currentTitle": Entry("Current title", "현재 제목"),

        // 직접 수정
        "edit.currentPrefix": Entry("Current: %@", "현재: %@"),
        "edit.failReasonTitle": Entry("Why identification failed", "식별 실패 이유"),
        "edit.section.songInfo": Entry("Track info", "곡 정보"),
        "edit.section.numbers": Entry("Numbers", "번호"),
        "edit.invalidNumbers": Entry("Enter numbers only: %@", "숫자만 입력하세요: %@"),
        "edit.reidentifyFailed": Entry("Couldn’t re-identify", "다시 식별하지 못했습니다"),
        "edit.writeNote": Entry("Entered values are written even if they differ from the current ones. Blank fields are left unchanged. The state before applying is kept as a snapshot you can undo.", "입력한 값은 기존 값과 달라도 그대로 씁니다. 빈 칸은 바꾸지 않습니다. 적용 전 상태는 스냅샷으로 남아 되돌릴 수 있습니다."),
        "edit.identifying": Entry("Identifying…", "식별 중…"),
        "edit.reidentifyButton": Entry("Identify", "이 정보로 다시 식별"),
        "edit.preview.play": Entry("Preview", "미리 듣기"),
        "edit.preview.pause": Entry("Pause", "일시정지"),
        "edit.preview.unavailableTitle": Entry("Can’t play this track", "이 곡을 재생할 수 없습니다"),
        "edit.preview.unavailableMsg": Entry("The audio file couldn’t be found or can’t be played (e.g., cloud-only or DRM-protected).", "오디오 파일을 찾을 수 없거나 재생할 수 없습니다 (클라우드 전용·DRM 보호 등)."),
        "edit.reidentify.help": Entry("Searches just this track again on MusicBrainz · iTunes · AcoustID using the entered title/artist/album. Your library isn’t changed. (Same as “Identify” on the main screen)", "입력한 제목·가수·앨범으로 이 곡만 MusicBrainz·iTunes·AcoustID에서 다시 찾아 봅니다. 보관함은 바꾸지 않습니다. (메인 화면의 ‘식별 실행’과 같은 기능)"),
        "edit.save": Entry("Save", "저장"),
        "edit.saveApply": Entry("Save & apply", "저장 후 적용"),
        "edit.noCoversTitle": Entry("No artwork found", "검색된 앨범커버가 없습니다"),
        "edit.noCoversMsg": Entry("No artwork was found for the entered title/artist/album. Try changing the values.", "입력된 곡 제목·가수·앨범으로 커버를 찾지 못했습니다. 값을 바꿔 다시 시도해 보세요."),
        "edit.reidentifying": Entry("Re-identifying with the entered info…", "입력한 정보로 다시 식별 중…"),
        "edit.reResultNotFound": Entry("Re-identified but found nothing", "다시 식별했지만 찾지 못했습니다"),
        "edit.reResult": Entry("Re-identify result: %@", "다시 식별 결과: %@"),
        "edit.applyResult": Entry("Apply result", "식별 결과로 적용"),
        "edit.applyResult.help": Entry("Applies the proposed values below right away (changes on apply: %@)", "아래 제안값을 바로 적용합니다 (적용 시 변경: %@)"),
        "edit.coverSuffix": Entry(" · Artwork: %@", " · 커버: %@"),
        "edit.filledNote": Entry("The fields below were filled with the result too. You can edit and “Save & apply.”", "아래 칸에도 식별 결과를 채웠습니다. 고쳐서 ‘저장 후 적용’해도 됩니다."),
        "edit.coverSearching": Entry("Searching artwork…", "앨범커버 검색 중…"),
        "edit.coverSearch": Entry("Search artwork", "앨범커버 검색"),
        "edit.coverSearch.help": Entry("Searches iTunes · Deezer for artwork using the entered title/artist/album.", "입력된 곡 제목·가수·앨범으로 iTunes·Deezer에서 앨범커버를 찾습니다."),
        "edit.pickFile": Entry("Choose image file…", "이미지 파일 선택…"),
        "edit.pasteClipboard": Entry("Paste from clipboard", "클립보드에서 붙여넣기"),
        "edit.clearSelection": Entry("Clear selection", "선택 취소"),
        "edit.art.replaceWithSelected": Entry("Replaces the existing artwork with the selected image", "선택한 이미지로 기존 커버를 바꿉니다"),
        "edit.art.useSelected": Entry("Adds the selected image as the artwork", "선택한 이미지를 커버로 넣습니다"),
        "edit.art.keepExisting": Entry("Keeps the existing artwork", "기존 커버를 유지합니다"),
        "edit.art.useProposed": Entry("Adds the proposed artwork (%@)", "제안된 커버(%@)를 넣습니다"),
        "edit.art.none": Entry("No artwork — you can choose an image", "커버 없음 — 이미지를 선택할 수 있습니다"),
        "edit.coverPicker.title": Entry("Choose artwork", "앨범커버 선택"),
        "edit.coverPicker.desc": Entry("Pick one of the %d artworks found. It goes into the image area and is written to the file on save.", "찾은 커버 %d개 중 하나를 고르세요. 선택하면 이미지 영역에 들어가고, 저장 시 실제 파일에 기록됩니다."),

        // 온보딩
        "onb.step.welcome": Entry("Welcome", "환영합니다"),
        "onb.step.howItWorks": Entry("How it works", "사용 방법"),
        "onb.step.permissions": Entry("Permissions", "권한 허용"),
        "onb.step.playlists": Entry("Playlists", "대상 플레이리스트"),
        // 사용 방법(핵심 기능 흐름)
        "onb.how.intro": Entry("Clean up your tags in four steps.", "네 단계로 태그를 정리합니다."),
        "onb.how.scan.title": Entry("1. Scan — find what needs work", "1. 스캔 — 정리 대상 찾기"),
        "onb.how.scan.detail": Entry("From the playlists you choose, it lists only tracks missing artwork, title, artist, or album.", "선택한 플레이리스트에서 앨범커버·제목·가수·앨범이 비어 있는 곡만 추려 보여 줍니다."),
        "onb.how.scan.detail2": Entry("Already-complete tracks are left alone, so you focus only on what matters.", "이미 완비된 곡은 건드리지 않아, 손봐야 할 곡에만 집중할 수 있습니다."),
        "onb.how.identify.title": Entry("2. Identify — get the right info", "2. 식별 — 올바른 정보 받기"),
        "onb.how.identify.detail": Entry("Looks up each track on MusicBrainz · iTunes · audio fingerprint and proposes the correct tags and artwork.", "각 곡을 MusicBrainz·iTunes·오디오 지문으로 조회해 올바른 태그와 앨범커버를 제안합니다."),
        "onb.how.identify.detail2": Entry("Each proposal gets a confidence level (High / Medium / Low) so you can trust strong matches at a glance.", "각 제안에 신뢰도(높음·보통·낮음)가 매겨져, 확실한 결과를 한눈에 믿고 쓸 수 있습니다."),
        "onb.how.review.title": Entry("3. Review — check and refine", "3. 검토 — 확인하고 다듬기"),
        "onb.how.review.detail": Entry("Approve or reject by album, or open Edit to fix values by hand and preview the track.", "앨범 단위로 승인·거부하거나, ‘직접 수정’에서 값을 손보고 미리 들어볼 수 있습니다."),
        "onb.how.review.detail2": Entry("Nothing is written until you decide — you stay in control.", "직접 결정하기 전에는 아무것도 기록되지 않아, 항상 통제권은 사용자에게 있습니다."),
        "onb.how.apply.title": Entry("4. Apply — write safely", "4. 적용 — 안전하게 반영"),
        "onb.how.apply.detail": Entry("Confirmed values and artwork are written to your Music library and verified.", "확인한 값과 앨범커버를 Music 보관함에 기록하고 다시 읽어 확인합니다."),
        "onb.how.apply.detail2": Entry("Every change keeps a snapshot, so you can undo any track, album, or whole run anytime.", "모든 변경은 스냅샷을 남겨, 곡·앨범·작업 단위로 언제든 되돌릴 수 있습니다."),
        "onb.how.note": Entry("Your library changes only when you press Apply — and everything is undoable.", "‘적용’을 누를 때만 보관함이 바뀌며, 모든 변경은 되돌릴 수 있습니다."),
        "onb.welcome.body": Entry("From the Music playlists you choose, it finds only tracks missing any of artwork, title, artist, or album, then identifies and proposes the missing info. Only tracks you confirm are applied, and every change can be undone.", "선택한 Music 플레이리스트에서 앨범커버·곡 제목·가수명·앨범명 중 하나라도 비어 있는 곡만 찾아, 빈 정보를 식별해 제안합니다. 확인한 곡만 적용하고, 모든 변경은 되돌릴 수 있습니다."),
        "onb.welcome.point1": Entry("Tracks that are already complete, and tracks in playlists you didn’t select, are left untouched.", "이미 정보가 모두 채워진 곡과 선택하지 않은 플레이리스트의 곡은 건드리지 않습니다."),
        "onb.welcome.point2": Entry("Your Music library changes only when you review results and press Apply yourself. Every change keeps a snapshot you can undo.", "식별 결과를 확인하고 직접 ‘적용’을 누를 때만 Music 보관함을 바꿉니다. 모든 변경은 스냅샷을 남겨 되돌릴 수 있습니다."),
        "onb.perm.intro": Entry("Two permissions are needed. Allow once and you won’t be asked again.", "두 가지 권한이 필요합니다. 한 번 허용하면 다시 묻지 않습니다."),
        "onb.perm.automation.title": Entry("Control Music app", "Music 앱 제어"),
        "onb.perm.automation.detail": Entry("Writes track info and artwork through the Music app. If Music is closed, it’s launched in the background.", "곡 정보와 커버를 Music 앱을 통해 기록합니다. Music이 꺼져 있으면 백그라운드로 실행합니다."),
        "onb.perm.media.title": Entry("Read Music library", "Music 보관함 읽기"),
        "onb.perm.media.detail": Entry("Reads playlists and track info directly. No XML export needed.", "플레이리스트와 곡 정보를 직접 읽습니다. XML 내보내기는 필요 없습니다."),
        "onb.perm.denied": Entry("Denied. Allow it in System Settings, then press “Recheck.”", "거부되어 있습니다. 시스템 설정에서 허용한 뒤 ‘다시 확인’을 누르세요."),
        "onb.perm.recheck": Entry("Recheck", "다시 확인"),
        "onb.perm.allow": Entry("Allow", "허용"),
        "onb.perm.openSettings": Entry("Open System Settings", "시스템 설정 열기"),
        "onb.perm.laterNote": Entry("You can allow these later in Settings, but scanning and applying won’t work until both are granted.", "설정에서 나중에 허용할 수 있지만, 두 권한을 모두 허용하기 전에는 스캔·적용이 동작하지 않습니다."),
        "onb.perm.granted.a11y": Entry("Granted", "허용됨"),
        "onb.playlists.intro": Entry("Choose playlists to clean up. Choosing a folder includes all playlists inside it.", "정리할 플레이리스트를 고르세요. 폴더를 고르면 안에 든 플레이리스트가 모두 포함됩니다."),
        "onb.footer.back": Entry("Back", "이전"),
        "onb.footer.start": Entry("Start", "시작"),
        "onb.footer.next": Entry("Next", "다음"),
        "onb.footer.later": Entry("Set up later", "나중에"),
        "onb.footer.close": Entry("Close", "닫기"),
        "onb.hint.permissions": Entry("Allow both permissions to continue", "두 권한을 모두 허용해야 계속할 수 있습니다"),
        "onb.hint.playlists": Entry("Select at least one playlist", "플레이리스트를 1개 이상 선택하세요"),

        // 플레이리스트 피커
        "pp.intro": Entry("Every checked playlist becomes a target. To switch to a different one, click a name to “Select only this,” or uncheck existing items.", "체크한 플레이리스트가 모두 대상이 됩니다. 다른 플레이리스트로 바꾸려면 이름을 눌러 ‘이것만 선택’하거나, 기존 항목의 체크를 해제하세요."),
        "pp.search": Entry("Search playlists", "플레이리스트 검색"),
        "pp.myPlaylists": Entry("My playlists", "내 플레이리스트"),
        "pp.wholeLibraryRow": Entry("Whole library (may be slow)", "전체 라이브러리 (느릴 수 있음)"),
        "pp.wholeLibraryFooter": Entry("Targets every track in the library. With many tracks, processing takes longer.", "보관함의 모든 곡을 대상으로 합니다. 곡이 많으면 처리 시간이 길어집니다."),
        "pp.selected": Entry("Selected", "선택됨"),
        "pp.removeFromSelection": Entry("Remove from selection", "선택에서 빼기"),
        "pp.deselectAll": Entry("Deselect all", "모두 해제"),
        "pp.coveredByAncestor": Entry("Included automatically by selecting a parent folder", "상위 폴더를 선택해 자동으로 포함됩니다"),
        "pp.selectOnly": Entry("Select only this", "이것만 선택"),
        "pp.selectOnly.help": Entry("Clears all other selections and targets only this playlist", "다른 선택을 모두 풀고 이 플레이리스트만 대상으로 합니다"),
        "pp.count": Entry("%d tracks", "%d곡"),
        "pp.countNeeds": Entry("%1$d tracks · %2$d need work", "%1$d곡 · 정리 필요 %2$d곡"),

        // 적용 상태 (MTMCore)
        "applyState.planned": Entry("Pending", "대기"),
        "applyState.writing": Entry("Writing", "쓰는 중"),
        "applyState.verified": Entry("Done", "완료"),
        "applyState.verifyFailed": Entry("Verify failed", "검증 실패"),
        "applyState.failed": Entry("Failed", "실패"),
        "applyState.skippedChanged": Entry("Skipped (edited)", "건너뜀 (직접 수정됨)"),
        "applyState.skippedNothing": Entry("Skipped (nothing to write)", "건너뜀 (쓸 값 없음)"),
        "applyState.cancelled": Entry("Cancelled", "취소됨"),

        // 작업 이력
        "history.job.undo": Entry("Undo #%d", "되돌리기 #%d"),
        "history.job.undoOf": Entry(" (job #%d)", " (작업 #%d)"),
        "history.job.apply": Entry("Apply #%d", "적용 #%d"),
        "history.summary.done": Entry("done %d", "완료 %d"),
        "history.summary.failed": Entry("failed %d", "실패 %d"),
        "history.summary.skipped": Entry("skipped %d", "건너뜀 %d"),
        "history.summary.unfinished": Entry("unfinished", "미완료"),
        "history.empty.title": Entry("No jobs yet", "아직 작업이 없습니다"),
        "history.empty.desc": Entry("Choose tracks in Results and apply them to see them recorded here.", "식별 결과에서 곡을 골라 적용하면 여기에 기록됩니다."),
        "history.confirmUndo.title": Entry("Undo %@?", "%@을(를) 되돌릴까요?"),
        "history.undo": Entry("Undo", "되돌리기"),
        "history.confirmUndo.msg": Entry("Restores the snapshot taken before the change. Tracks you edited after applying are skipped. The undo is also recorded in History.", "변경 전 스냅샷으로 복원합니다. 적용 이후 직접 고친 곡은 건너뜁니다. 되돌리기도 작업 이력에 남습니다."),
        "history.resume": Entry("Resume", "이어서 실행"),
        "history.cancelRemaining": Entry("Cancel remaining", "남은 곡 취소"),
        "history.undoWholeJob": Entry("Undo this entire job", "이 작업 전체 되돌리기"),
        "history.undoDescWholeJob": Entry("all changes in %@", "%@의 모든 변경"),
        "history.changed": Entry("Changed: %@", "변경: %@"),
        "history.undone": Entry("Undone", "되돌림"),
        "history.undoTrack": Entry("Undo this track", "이 곡만 되돌리기"),
        "history.undoDescTrack": Entry("changes to “%@”", "‘%@’의 변경"),

        // 검수표 가져오기
        "import.title": Entry("Import review sheet", "검수표 가져오기"),
        "import.overridesLabel": Entry("Edited values", "값을 고친 곡"),
        "import.overridesValue": Entry("%d tracks → saved as “Edit”", "%d곡 → ‘직접 수정’으로 저장"),
        "import.rejectLabel": Entry("Rejected", "거절"),
        "import.rejectValue": Entry("%d tracks → applied", "%d곡 → 반영됨"),
        "import.approveLabel": Entry("Approved", "승인"),
        "import.approveValue": Entry("%d tracks → apply with the button below", "%d곡 → 아래 버튼으로 적용"),
        "import.unchangedLabel": Entry("No change", "변경 없음"),
        "import.unchangedValue": Entry("%d tracks", "%d곡"),
        "import.errorsTitle": Entry("%d rows need attention", "확인이 필요한 행 %d개"),
        "import.applyApproved": Entry("Apply %d approved tracks", "승인한 %d곡 적용"),

        // 앱 루트·시작·완료 알림
        "root.launching": Entry("Checking the Music library…", "Music 보관함 확인 중…"),
        "root.failed.title": Entry("Can’t start", "시작할 수 없습니다"),
        "root.removedPlaylist.title": Entry("Playlists dropped from scope", "선택에서 빠진 플레이리스트"),
        "root.removedPlaylist.msg": Entry("Removed from the scope because they were deleted from the library: %@", "보관함에서 삭제되어 대상에서 자동으로 뺐습니다: %@"),
        "completion.detailNote": Entry("See reasons for failures/skips by clicking a result’s status or in History.", "실패·건너뜀 사유는 식별 결과의 상태를 누르거나 작업 이력에서 볼 수 있습니다."),
        "completion.dontShowAgain": Entry("Don’t show again", "다시 표시하지 않기"),
        "completion.title.done": Entry("Applied", "적용을 마쳤습니다"),
        "completion.title.unfinished": Entry("Couldn’t finish applying", "적용을 마치지 못했습니다"),
        "completion.done": Entry("%d done", "완료 %d곡"),
        "completion.failed": Entry("%d failed", "실패 %d곡"),
        "completion.skipped": Entry("%d skipped", "건너뜀 %d곡"),
        "completion.unfinished": Entry("%d left", "남음 %d곡"),

        // 진행 표시(Activity) 제목
        "activity.scanning": Entry("Scanning", "검사 중"),
        "activity.identify": Entry("Identifying", "식별"),
        "activity.tidying": Entry("Finalizing", "결과 정리 중"),
        "activity.fingerprint": Entry("Fingerprint search", "오디오 지문 검색"),
        "activity.coverStatus": Entry("Checking artwork", "커버 상태 확인"),
        "activity.coverCandidates": Entry("Checking artwork candidates", "커버 후보 확인"),
        "activity.apply": Entry("Applying", "적용"),

        // 상태 사유 / 오류 메시지 (AppState)
        "reason.rejectedDetail": Entry("This track was undone. Re-running identification brings it back to the review queue.", "되돌린 곡입니다. 식별을 다시 실행하면 검토 대기로 돌아옵니다."),
        "reason.remaining": Entry("%@ still remain after applying", "적용 후에도 %@이(가) 남아 있습니다"),
        "reason.errorPrefix": Entry("Error: %@", "오류: %@"),
        "reason.noCandidate": Entry("No candidates", "후보 없음"),
        "reason.noCandidateDetail": Entry("No candidates (details are recorded when you re-run identification)", "후보 없음 (자세한 이유는 식별을 다시 실행하면 기록됩니다)"),
        "reason.noTrackInfo": Entry("No track info", "곡 정보 없음"),
        "reason.reidentifiedWithInput": Entry("Re-identified with entered info", "입력한 정보로 다시 식별"),
        "err.dbOpen": Entry("Couldn’t open the database: %@", "데이터베이스를 열 수 없습니다: %@"),
        "err.identifyOffline": Entry("Stopped identification: not connected to the network. Reconnect and run again to continue from the remaining tracks.", "네트워크에 연결되어 있지 않아 식별을 멈췄습니다. 연결한 뒤 다시 실행하면 남은 곡부터 이어서 합니다."),
        "err.identifyFailed": Entry("Couldn’t finish identification: %@", "식별을 마치지 못했습니다: %@"),
        "err.reidentifyOffline": Entry("Couldn’t re-identify: not connected to the network.", "네트워크에 연결되어 있지 않아 다시 식별하지 못했습니다."),
        "err.reidentifyFailed": Entry("Couldn’t re-identify: %@", "다시 식별하지 못했습니다: %@"),
        "err.noApplicable": Entry("No applicable proposals (excludes unidentified, nothing-to-change, rejected, and in-progress tracks)", "적용할 수 있는 제안이 없습니다 (식별 실패·바꿀 값 없음·거절·이미 진행 중인 곡 제외)"),
        "err.createJobFailed": Entry("Couldn’t create the job: %@", "작업을 만들지 못했습니다: %@"),
        "err.copyCoverFailed": Entry("Couldn’t copy the artwork file: %@", "커버 파일을 복사하지 못했습니다: %@"),
        "err.saveFailed": Entry("Couldn’t save: %@", "저장하지 못했습니다: %@"),
        "err.exportSheetFailed": Entry("Couldn’t save the review sheet: %@", "검수표를 저장하지 못했습니다: %@"),
        "err.importSheetFailed": Entry("Couldn’t read the review sheet (check it’s UTF-8 CSV): %@", "검수표를 읽지 못했습니다 (UTF-8 CSV인지 확인하세요): %@"),
        "err.setArtworkFailed": Entry("Couldn’t set the artwork: %@", "커버를 지정하지 못했습니다: %@"),
        "err.rejectFailed": Entry("Couldn’t reject: %@", "거절하지 못했습니다: %@"),
        "err.nothingToUndo": Entry("No changes to undo", "되돌릴 변경이 없습니다"),
        "err.createUndoFailed": Entry("Couldn’t create the undo job: %@", "되돌리기 작업을 만들지 못했습니다: %@"),
        "err.launchMusicFailed": Entry("Couldn’t launch the Music app", "Music 앱을 실행할 수 없습니다"),
        "err.jobStopped": Entry("Stopped the job: %@ — fix the problem and resume from History.", "작업을 멈췄습니다: %@ — 문제를 해결한 뒤 작업 이력에서 이어서 실행할 수 있습니다"),
        "err.cancelFailed": Entry("Couldn’t cancel the job: %@", "작업을 취소하지 못했습니다: %@"),

        // 커버 서비스 (MTMCore)
        "art.err.notImage": Entry("Not an image", "이미지가 아닙니다"),
        "art.err.tooSmall": Entry("Low resolution (%d×%d)", "해상도가 낮습니다 (%d×%d)"),
        "art.err.notSquare": Entry("Not square (%d×%d)", "정사각형이 아닙니다 (%d×%d)"),
        "art.err.unavailable": Entry("Couldn’t fetch the artwork", "커버를 가져올 수 없습니다"),
        "art.fail.offline": Entry("No network connection", "네트워크 연결 없음"),
        "art.fail.saveFailed": Entry("Couldn’t save artwork file: %@", "커버 파일 저장 실패: %@"),
        "art.src.sameAlbum": Entry("Same-album track", "같은 앨범 곡"),
        "art.src.selectedFile": Entry("Selected file", "선택한 파일"),
        "art.src.caaRep": Entry("Cover Art Archive (group)", "Cover Art Archive(대표)"),
        "art.check.unusable": Entry("Unusable", "쓸 수 없음"),
        "art.err.tooSmallLabel": Entry("Low resolution", "해상도가 낮습니다"),
        "art.err.notSquareLabel": Entry("Not square", "정사각형이 아닙니다"),

        // 적용 서비스 (MTMCore)
        "apply.err.badID": Entry("Invalid track ID", "잘못된 곡 ID"),
        "apply.err.noSnapshot": Entry("No snapshot", "스냅샷 없음"),
        "apply.err.notFound": Entry("Track not found in the Music library", "Music 보관함에서 곡을 찾을 수 없습니다"),
        "apply.skip.changed": Entry("“%@” appears to have been edited in Music since the scan, so it wasn’t applied. Check the values in “Edit” and apply.", "검사 이후 Music에서 ‘%@’ 값이 사용자가 직접 바꾼 것으로 보여 적용하지 않았습니다. ‘직접 수정’에서 값을 확인해 적용하세요."),
        "apply.note.lowResUsed": Entry("Using low-resolution artwork (%d×%d)", "저해상도 커버 사용 (%d×%d)"),
        "apply.note.coverSkipped": Entry("Artwork not applied — %@", "커버 미적용 — %@"),
        "apply.undo.nothing": Entry("No changes to undo", "되돌릴 변경이 없습니다"),
        "apply.undo.fieldEdited": Entry("%@ was edited after applying, so it wasn’t undone", "적용 이후 %@이(가) 직접 수정되어 되돌리지 않았습니다"),
        "apply.undo.coverDeleted": Entry("The artwork was deleted after applying, so it wasn’t undone", "적용 이후 커버가 직접 삭제되어 되돌리지 않았습니다"),
        "apply.undo.alreadyOriginal": Entry("Already the original value", "이미 원래 값입니다"),
        "apply.verify.rereadFail": Entry("Couldn’t re-read the track after applying", "적용 후 곡을 다시 읽을 수 없습니다"),
        "apply.verify.mismatch": Entry("Re-read values differ: %@", "다시 읽은 값이 다릅니다: %@"),

        // 식별 사유 (MTMCore AlbumResolver)
        "resolve.noAlbumName": Entry("No album name", "앨범명 없음"),
        "resolve.noTitle": Entry("No title to search (track title is empty and nothing found from the filename)", "검색할 제목 없음 (곡 제목이 비어 있고 파일명에서도 찾지 못함)"),
        "resolve.noAcoustID": Entry("Audio fingerprint not checked (AcoustID off or no API key)", "오디오 지문 확인 안 함 (AcoustID 꺼짐 또는 API 키 없음)"),
        "resolve.fp.drm": Entry("DRM-protected track, so no audio fingerprint can be made (identify by title/artist only)", "DRM 보호 곡이라 오디오 지문을 만들 수 없습니다 (제목·가수로만 식별)"),
        "resolve.fp.cloud": Entry("Cloud-only track — download it in Music first to identify by audio fingerprint", "클라우드 전용 곡 — Music에서 먼저 다운로드하면 오디오 지문으로 식별할 수 있습니다"),
        "resolve.fp.noLocation": Entry("Can’t make an audio fingerprint: file location unknown", "파일 위치를 알 수 없어 오디오 지문을 만들 수 없습니다"),
        "resolve.fp.fileMissing": Entry("Can’t make an audio fingerprint: local file not found: %@", "로컬 파일을 찾을 수 없어 오디오 지문을 만들 수 없습니다: %@"),
        "resolve.fp.noMatch": Entry("Audio fingerprint: no matching recording on AcoustID", "오디오 지문: AcoustID에 일치하는 녹음 없음"),
        "resolve.artistNotFound": Entry("Couldn’t find artist “%@” on MusicBrainz (searched without artist)", "가수 ‘%@’을(를) MusicBrainz에서 찾지 못함 (가수 없이 검색)"),
        "resolve.searchMB": Entry("MusicBrainz search “%@”", "MusicBrainz 검색 ‘%@’"),
        "resolve.searchArtistSuffix": Entry(" · %@", " · %@"),
        "resolve.searchNoArtist": Entry(" (artist unknown → title+length)", " (가수 모름 → 제목+길이)"),
        "resolve.searchNoResult": Entry("%@: no results", "%@: 결과 없음"),
        "resolve.searchWhat.titleLen": Entry("title·length (±3s)", "제목·길이(±3초)"),
        "resolve.searchWhat.titleArtist": Entry("title·artist", "제목·가수"),
        "resolve.searchNoMatch": Entry("%1$@: no track matching %2$@ among %3$d results (e.g., %4$@ — %5$@)", "%1$@: 결과 %3$d건 중 %2$@가 맞는 곡 없음 (예: %4$@ — %5$@)"),
        "resolve.noAlbumForRecording": Entry("No album info for the found track “%@”", "찾은 곡 ‘%@’이(가) 실린 앨범 정보가 없음"),
        "resolve.itunesNoMatch": Entry("iTunes song search “%@”: no track matching title/artist", "iTunes 노래 검색 ‘%@’: 제목·가수가 맞는 곡 없음"),

        // 신뢰도 근거 (ConfidenceScorer)
        "scorer.fingerprint": Entry("Fingerprint match", "오디오 지문 일치"),
        "scorer.albumFingerprint": Entry("Fingerprint confirmed on a same-album track", "같은 앨범 곡의 지문 확인"),
        "scorer.titleExact": Entry("Title match", "제목 일치"),
        "scorer.titleClose": Entry("Title similar", "제목 유사"),
        "scorer.artistExact": Entry("Artist match", "가수 일치"),
        "scorer.artistClose": Entry("Artist similar", "가수 유사"),
        "scorer.albumExact": Entry("Album match", "앨범명 일치"),
        "scorer.duration": Entry("Length within 3s", "길이 차이 3초 이내"),
        "scorer.trackCount": Entry("Album track count matches", "앨범 트랙 수 일치"),
        "scorer.sourcesAgree": Entry("Two or more sources agree", "2개 이상 소스 일치"),
        "scorer.ambiguous": Entry("Several similar candidates", "비슷한 후보가 여럿"),
        "scorer.coreMismatch": Entry("Differs from existing title/artist", "기존 제목·가수와 불일치"),
        "scorer.artistReplaced": Entry("Artist changed to a different person → not auto-applied", "가수가 다른 사람으로 바뀜 → 자동 적용 안 함"),

        // 미리보기 사유 (ProposalRecord.preview)
        "preview.overrideSame": Entry("Entered value is the same as the current value", "입력한 값이 현재 값과 같음"),
        "preview.identifyFailed": Entry("Not identified — edit directly to apply", "식별 실패 — 직접 수정해 적용할 수 있습니다"),
        "preview.noCover": Entry("No artwork — %@", "커버 없음 — %@"),
        "preview.noCoverCandidateDiffAlbum": Entry("No artwork candidate — identified album (%@) differs from the local album", "커버 후보 없음 — 식별된 앨범(%@)이 로컬 앨범과 다름"),
        "preview.noCoverCandidate": Entry("No artwork candidate", "커버 후보 없음"),
        "preview.nothingToChange": Entry("Nothing to change (kept per policy)", "바꿀 값 없음 (정책상 유지)"),

        // 대시보드 (중복곡)
        "dash.duplicatesOnly": Entry("Duplicates only", "중복곡 표시"),
        "dash.duplicatesOnly.help": Entry("When on, shows only tracks that appear more than once (same title · artist) in the Complete list.", "켜면 완비 목록에서 제목·가수가 같은 중복곡만 보여 줍니다."),
        "card.duplicateTracks": Entry("Duplicates", "중복곡"),
    ]
}
