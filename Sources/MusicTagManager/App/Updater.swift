import Foundation

#if canImport(Sparkle)
import Sparkle

/// Sparkle 자동 업데이트 래퍼. Apple 개발자 계정 없이 EdDSA(자체 키)로 업데이트를 검증한다.
/// `Info.plist`의 SUFeedURL(GitHub Releases의 appcast.xml) + SUPublicEDKey가 채워져 있을 때만 동작한다.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()
    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true → 실행 시 자동 확인 일정(Info.plist 설정)에 따라 동작
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
#endif

/// 업데이트 기능 진입점. Sparkle이 링크돼 있고(배포 빌드) 피드·공개키가 설정됐을 때만 노출된다.
/// (개발용 xcodeproj 빌드에 Sparkle이 없어도 `canImport`로 안전하게 비활성화된다.)
enum UpdateFeature {
    /// 메뉴·설정에 '업데이트 확인'을 보여 줄지
    static var isAvailable: Bool {
        #if canImport(Sparkle)
        return isConfigured
        #else
        return false
        #endif
    }

    /// 앱 시작 시 호출 — 설정돼 있으면 업데이터를 띄워 자동 확인을 시작한다.
    @MainActor static func start() {
        #if canImport(Sparkle)
        if isConfigured { _ = AppUpdater.shared }
        #endif
    }

    @MainActor static func checkForUpdates() {
        #if canImport(Sparkle)
        if isConfigured { AppUpdater.shared.checkForUpdates() }
        #endif
    }

    /// 피드 URL과 공개키가 실제 값으로 채워졌는지 (placeholder면 비활성 → 실행 오류 방지)
    private static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        guard let feed = info?["SUFeedURL"] as? String, feed.hasPrefix("http"),
              let key = info?["SUPublicEDKey"] as? String, !key.isEmpty, !key.contains("REPLACE")
        else { return false }
        return true
    }
}
