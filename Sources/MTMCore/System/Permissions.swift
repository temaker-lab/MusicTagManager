import AppKit
import CoreServices

public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    /// 확인 대상 앱(Music)이 실행 중이 아님
    case targetNotRunning
    case unknown(Int32)

    public var isGranted: Bool { self == .granted }
}

/// 온보딩에서 한 번만 요청하는 권한들
public enum Permissions {
    public static let musicBundleID = "com.apple.Music"

    /// Music 앱 제어(Apple Events) 권한. `ask == true`이면 아직 정하지 않은 경우 시스템 권한 창을 띄운다.
    /// 사용자가 응답할 때까지 호출 스레드를 막으므로 메인 스레드에서 부르지 않는다.
    public static func musicAutomationStatus(ask: Bool) -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: musicBundleID)
        guard let desc = target.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .targetNotRunning
        default:
            Log.permissions.error("Apple Events 권한 확인 결과: \(status)")
            return .unknown(status)
        }
    }

    public static var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == musicBundleID }
    }

    /// Music이 꺼져 있으면 백그라운드로 실행한다 (재생 상태는 건드리지 않음)
    public static func launchMusicIfNeeded(timeout: TimeInterval = 15) async -> Bool {
        if isMusicRunning { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isMusicRunning { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return isMusicRunning
    }

    public enum SettingsPane: String {
        case automation = "Privacy_Automation"
        case media = "Privacy_Media"
    }

    @MainActor
    public static func openSystemSettings(_ pane: SettingsPane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
