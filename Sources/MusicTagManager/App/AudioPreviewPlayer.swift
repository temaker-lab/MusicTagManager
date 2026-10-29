import AVFoundation
import MTMCore
import Observation

/// 직접 수정 팝업에서 곡을 미리 들을 때 쓰는 단일 재생기. 앱에 별도 오디오 재생 시스템이 없어 새로 둔다.
/// 로컬 파일(`LibraryTrack.fileURL`)을 그대로 재생하며, 재생/일시정지/재개/종료 상태를 관찰 가능하게 노출한다.
@MainActor
@Observable
final class AudioPreviewPlayer {
    /// 지금 로드된(재생 중이거나 일시정지된) 곡. 없으면 nil.
    private(set) var currentID: PersistentID?
    private(set) var isPlaying = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private lazy var delegate = FinishDelegate { [weak self] in self?.handleFinish() }

    /// 이 곡을 처음부터 재생한다. 파일을 열 수 없으면(없는 파일·DRM 등) false를 돌려준다.
    @discardableResult
    func play(id: PersistentID, url: URL) -> Bool {
        if currentID != id { stop() }
        if player == nil {
            guard let created = try? AVAudioPlayer(contentsOf: url) else { return false }
            created.delegate = delegate
            created.prepareToPlay()
            player = created
            currentID = id
        }
        player?.play()
        isPlaying = true
        return true
    }

    /// 지금 곡을 일시정지/재개 토글한다 (로드된 곡이 없으면 아무것도 안 함).
    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    /// 재생을 멈추고 상태를 비운다 (팝업을 닫거나 다른 곡으로 바뀔 때).
    func stop() {
        player?.stop()
        player = nil
        currentID = nil
        isPlaying = false
    }

    private func handleFinish() {
        player = nil
        currentID = nil
        isPlaying = false
    }

    /// AVAudioPlayer 종료 콜백을 메인 액터로 넘기는 작은 델리게이트
    private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in onFinish() }
        }
    }
}
