import Foundation

/// 쓰기 직전 상태. Core 모듈 밖에서는 만들 수 없으므로, 앱은 스냅샷 없이 Music에 쓸 수 없다.
public struct Snapshot: Sendable {
    public let jobID: Int64
    public let persistentID: PersistentID
    public let before: TrackFields
    /// 원래 커버를 바꾸는 경우 백업한 원본 파일
    public let beforeArtworkPath: String?

    init(jobID: Int64, persistentID: PersistentID, before: TrackFields, beforeArtworkPath: String?) {
        self.jobID = jobID
        self.persistentID = persistentID
        self.before = before
        self.beforeArtworkPath = beforeArtworkPath
    }
}

public enum WriteError: LocalizedError, Equatable {
    case snapshotMismatch
    case guardBlocked(libraryTracks: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .snapshotMismatch: return "스냅샷과 대상 곡이 다릅니다"
        case .guardBlocked(let count, let limit):
            return "안전장치: 현재 보관함 곡 \(count)개가 한도 \(limit)개를 넘어 쓰기를 멈췄습니다 (설정 > 일반에서 해제)"
        }
    }
}

/// Music 보관함의 유일한 쓰기 지점 (직렬 실행, 일시적 오류는 3회 재시도)
public actor LibraryWriter {
    private let music: MusicScripting
    /// 이 수보다 곡이 많은 보관함에는 쓰지 않는다 (nil = 해제)
    private let maxLibraryTracks: Int?
    private var guardCheckedAt: Date?
    private let retryDelay: TimeInterval

    public init(music: MusicScripting, maxLibraryTracks: Int?, retryDelay: TimeInterval = 0.5) {
        self.music = music
        self.maxLibraryTracks = maxLibraryTracks
        self.retryDelay = retryDelay
    }

    public func apply(_ change: TrackChange, snapshot: Snapshot) async throws {
        try await checkGuard()
        let id = snapshot.persistentID
        if !change.values.isEmpty {
            try await retrying { try await self.music.write(change.values, to: id) }
        }
        switch change.artwork {
        case .set(let path, _), .restore(let path):
            try await retrying { try await self.music.setArtwork(id, imageFile: URL(fileURLWithPath: path)) }
        case .delete:
            try await retrying { try await self.music.deleteArtwork(id) }
        case nil:
            break
        }
    }

    /// 보관함을 바꿨을 수 있으므로 1분마다 다시 확인
    private func checkGuard() async throws {
        guard let limit = maxLibraryTracks else { return }
        if let checked = guardCheckedAt, Date().timeIntervalSince(checked) < 60 { return }
        let count = try await music.libraryTrackCount()
        guard count <= limit else { throw WriteError.guardBlocked(libraryTracks: count, limit: limit) }
        guardCheckedAt = Date()
    }

    private func retrying(_ operation: @Sendable () async throws -> Void) async throws {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as MusicScriptError where !error.isPermanent && attempt < 2 {
                attempt += 1
                Log.apply.info("Music 쓰기 재시도 \(attempt): \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            }
        }
    }
}
