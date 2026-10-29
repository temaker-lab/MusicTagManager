import Foundation
import MTMCore

/// 사용자 설정. 아무것도 바꾸지 않아도 합리적으로 동작하도록 기본값을 둔다.
struct AppSettings: Codable, Equatable {
    var onboardingCompleted = false
    /// 화면 테마
    var appearance: AppearanceMode = .system
    /// 앱 언어 (system = 맥 설정에 따름)
    var language: AppLanguage = .system
    var rules = CompletenessRules()
    var identification = IdentificationSettings()
    /// MusicBrainz User-Agent 연락처 (MusicBrainz 이용 규칙상 필수)
    var musicBrainzContact = "rnap.00@gmail.com"
    var writePolicies = WritePolicies()
    /// 쓰기 전에 원본 음악 파일 전체를 백업 (기본 꺼짐: 메타데이터 스냅샷으로 되돌리기 가능)
    var fullFileBackup = false
    /// 선택·전체 적용이 끝나면 결과 알림
    var showApplyCompletionAlert = true
    /// 600px 이상 커버가 없으면 300px 이상 커버도 사용 (Cover Art Archive는 400~500px가 많음)
    var allowLowResolutionArtwork = true
    /// 되돌리기용 스냅샷 보존 기간(일). 이보다 오래된 스냅샷과 백업 파일은 자동 정리한다. 0 = 무제한 보관.
    var snapshotRetentionDays = 30
    /// 개발용 안전장치: 곡이 이보다 많은 보관함(메인 보관함)에는 쓰지 않는다
    var writeGuardEnabled = true
    static let writeGuardLimit = 3_000

    init() {}

    // 새 설정 항목이 추가돼도 예전에 저장한 설정을 읽을 수 있도록 항목별 기본값 사용
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? defaults.appearance
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? defaults.language
        // 하위 설정을 못 읽어도 온보딩 완료 여부 등 나머지는 유지한다
        rules = (try? c.decodeIfPresent(CompletenessRules.self, forKey: .rules)) ?? defaults.rules
        identification = (try? c.decodeIfPresent(IdentificationSettings.self, forKey: .identification)) ?? defaults.identification
        // v0.1 기본 목록을 그대로 쓰던 사용자에게는 새 기본값(`여러 음악가`)을 반영
        if rules.artistPlaceholders == ["Unknown Artist", "알 수 없는 아티스트", "Various", "Various Artists"] {
            rules.artistPlaceholders = defaults.rules.artistPlaceholders
        }
        musicBrainzContact = try c.decodeIfPresent(String.self, forKey: .musicBrainzContact) ?? defaults.musicBrainzContact
        writePolicies = (try? c.decodeIfPresent(WritePolicies.self, forKey: .writePolicies)) ?? defaults.writePolicies
        writeGuardEnabled = try c.decodeIfPresent(Bool.self, forKey: .writeGuardEnabled) ?? defaults.writeGuardEnabled
        allowLowResolutionArtwork = try c.decodeIfPresent(Bool.self, forKey: .allowLowResolutionArtwork) ?? defaults.allowLowResolutionArtwork
        snapshotRetentionDays = try c.decodeIfPresent(Int.self, forKey: .snapshotRetentionDays) ?? defaults.snapshotRetentionDays
        showApplyCompletionAlert = try c.decodeIfPresent(Bool.self, forKey: .showApplyCompletionAlert) ?? defaults.showApplyCompletionAlert
        fullFileBackup = try c.decodeIfPresent(Bool.self, forKey: .fullFileBackup) ?? defaults.fullFileBackup

    }
}

struct SettingsStore {
    private let key = "appSettings.v1"
    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
