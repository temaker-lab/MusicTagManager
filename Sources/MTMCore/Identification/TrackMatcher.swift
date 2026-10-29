import Foundation

/// 매칭에 쓰는 로컬 곡 정보. 비어 있는 값은 nil
public struct LocalTrackInfo: Sendable, Hashable {
    public var id: PersistentID
    public var title: String?
    public var durationMs: Int
    public var trackNumber: Int?
    public var discNumber: Int?
    /// 오디오 지문으로 확인된 녹음 ID
    public var recordingIDs: Set<String>

    public init(id: PersistentID, title: String?, durationMs: Int, trackNumber: Int? = nil, discNumber: Int? = nil,
                recordingIDs: Set<String> = []) {
        self.id = id
        self.title = title
        self.durationMs = durationMs
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.recordingIDs = recordingIDs
    }
}

public struct TrackMatch: Sendable, Hashable {
    public var releaseTrack: ReleaseTrack
    public var titleSimilarity: Double?
    public var durationDeltaMs: Int?
    public var positionMatches: Bool
    public var byFingerprint: Bool
}

/// 로컬 곡 ↔ 릴리스 트랙리스트 매칭 (제목 유사도 + 길이 ±3초 + 트랙 번호, 지문 녹음 ID 최우선)
public enum TrackMatcher {
    public static func match(_ locals: [LocalTrackInfo], to tracks: [ReleaseTrack]) -> [PersistentID: TrackMatch] {
        var pairs: [(score: Double, local: Int, track: Int, match: TrackMatch)] = []
        for (li, local) in locals.enumerated() {
            for (ti, track) in tracks.enumerated() {
                if let candidate = evaluate(local, track) {
                    pairs.append((candidate.score, li, ti, candidate.match))
                }
            }
        }
        // 점수 높은 쌍부터 1:1로 배정
        pairs.sort { $0.score > $1.score }
        var usedLocals = Set<Int>(), usedTracks = Set<Int>()
        var result: [PersistentID: TrackMatch] = [:]
        for pair in pairs where !usedLocals.contains(pair.local) && !usedTracks.contains(pair.track) {
            usedLocals.insert(pair.local)
            usedTracks.insert(pair.track)
            result[locals[pair.local].id] = pair.match
        }
        return result
    }

    static func evaluate(_ local: LocalTrackInfo, _ track: ReleaseTrack) -> (score: Double, match: TrackMatch)? {
        let delta = track.durationMs.map { abs($0 - local.durationMs) }
        let positionMatches = local.trackNumber == track.trackNumber && (local.discNumber ?? 1) == track.discNumber
        if let recording = track.recordingID, local.recordingIDs.contains(recording) {
            return (200, TrackMatch(releaseTrack: track, titleSimilarity: local.title.map { Normalizer.similarity($0, track.title) },
                                    durationDeltaMs: delta, positionMatches: positionMatches, byFingerprint: true))
        }
        var score = 0.0
        let similarity = local.title.map { Normalizer.similarity($0, track.title) }
        if let similarity {
            score += similarity * 60
            if Normalizer.versionTags(local.title) != Normalizer.versionTags(track.title) { score -= 40 }
        }
        if let delta, local.durationMs > 0 {
            score += delta <= 3_000 ? 25 : delta <= 10_000 ? 5 : -10
        }
        if positionMatches { score += 15 }
        // 제목을 모르는 곡은 길이와 트랙 번호가 모두 맞아야 한다
        let threshold = similarity == nil ? 40.0 : 55.0
        guard score >= threshold else { return nil }
        return (score, TrackMatch(releaseTrack: track, titleSimilarity: similarity, durationDeltaMs: delta,
                                  positionMatches: positionMatches, byFingerprint: false))
    }
}
