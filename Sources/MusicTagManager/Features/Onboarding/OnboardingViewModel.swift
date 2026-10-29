import Foundation
import MTMCore
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    /// 최초 실행(firstRun)과 설정에서 '다시 보기'(replay)를 구분한다.
    /// replay는 사용자의 현재 범위·데이터를 바꾸지 않고 안내만 다시 보여 준 뒤 닫는다.
    enum Mode { case firstRun, replay }

    enum Step: Int {
        case welcome, howItWorks, permissions, playlists

        var title: String {
            switch self {
            case .welcome: return L("onb.step.welcome")
            case .howItWorks: return L("onb.step.howItWorks")
            case .permissions: return L("onb.step.permissions")
            case .playlists: return L("onb.step.playlists")
            }
        }
    }

    let mode: Mode
    /// 이 모드에서 실제로 보여 줄 단계 순서 (replay는 범위 선택을 건드리지 않으려고 playlists 제외)
    let steps: [Step]
    private(set) var index = 0
    var step: Step { steps[index] }

    private(set) var automation: PermissionStatus = .notDetermined
    private(set) var media: PermissionStatus = .notDetermined
    private(set) var mediaError: String?
    private(set) var isRequestingAutomation = false
    private(set) var isRequestingMedia = false
    private(set) var isFinishing = false
    /// 권한을 '나중에'(설정에서 나중에 허용) 하기로 한 경우
    private(set) var permissionsSkipped = false

    let picker: PlaylistPickerViewModel
    private let state: AppState
    private let onClose: (() -> Void)?

    init(state: AppState, mode: Mode = .firstRun, onClose: (() -> Void)? = nil) {
        self.state = state
        self.mode = mode
        self.onClose = onClose
        steps = mode == .firstRun ? [.welcome, .howItWorks, .permissions, .playlists]
                                  : [.welcome, .howItWorks, .permissions]
        picker = PlaylistPickerViewModel(state: state)
    }

    var isFirstStep: Bool { index == 0 }
    var isLastStep: Bool { index == steps.count - 1 }

    /// 권한이 모두 허용됐는가 (또는 '나중에'로 넘어갔는가)
    private var permissionsReady: Bool { (automation.isGranted && media.isGranted) || permissionsSkipped }

    var canGoNext: Bool {
        switch step {
        case .welcome, .howItWorks: return true
        case .permissions: return permissionsReady
        case .playlists: return picker.hasSelection && !isFinishing
        }
    }

    /// 권한 단계에서 아직 허용되지 않아 '나중에' 버튼을 보여 줄지
    var canSkipPermissions: Bool { step == .permissions && !(automation.isGranted && media.isGranted) }

    var nextHint: String? {
        switch step {
        case .permissions where !permissionsReady: return L("onb.hint.permissions")
        case .playlists where !canGoNext: return L("onb.hint.playlists")
        default: return nil
        }
    }

    /// 이미 허용된 권한은 다시 묻지 않도록 조용히 확인한다.
    func refreshAutomationSilently() async {
        guard Permissions.isMusicRunning else { return }
        automation = await Task.detached { Permissions.musicAutomationStatus(ask: false) }.value
    }

    /// 실제 Apple Event 권한 요청 → 시스템 권한 창
    func requestAutomation() async {
        isRequestingAutomation = true
        defer { isRequestingAutomation = false }
        guard await Permissions.launchMusicIfNeeded() else {
            automation = .targetNotRunning
            return
        }
        automation = await Task.detached { Permissions.musicAutomationStatus(ask: true) }.value
    }

    /// ITLibrary 연결 = '미디어 및 Apple Music' 권한 확인
    func requestMedia() async {
        isRequestingMedia = true
        defer { isRequestingMedia = false }
        do {
            try await state.loadCatalog()
            media = .granted
            mediaError = nil
        } catch {
            media = .denied
            mediaError = error.localizedDescription
        }
    }

    /// 권한을 '나중에'로 미루고 다음으로 (앱은 설정에서 언제든 허용할 수 있다)
    func skipPermissions() async {
        permissionsSkipped = true
        await goNext()
    }

    func goNext() async {
        guard canGoNext else { return }
        if isLastStep {
            await finish()
            return
        }
        index += 1
        switch step {
        case .permissions: await refreshAutomationSilently()
        case .playlists: await picker.load()
        default: break
        }
    }

    func goBack() {
        guard index > 0 else { return }
        index -= 1
    }

    /// replay에서 아무 때나 닫기
    func close() { onClose?() }

    private func finish() async {
        switch mode {
        case .firstRun:
            isFinishing = true
            await state.finishOnboarding(selection: picker.selection)
        case .replay:
            onClose?()
        }
    }
}
