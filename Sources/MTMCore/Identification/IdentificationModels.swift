import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case musicbrainz, itunes, acoustid, deezer
}

/// 릴리스 트랙리스트의 한 곡
public struct ReleaseTrack: Codable, Hashable, Sendable {
    public var discNumber: Int
    public var trackNumber: Int
    public var title: String
    public var artist: String
    public var artistIDs: [String]
    public var durationMs: Int?
    public var recordingID: String?
    public var isrc: String?

    public init(discNumber: Int, trackNumber: Int, title: String, artist: String, artistIDs: [String] = [],
                durationMs: Int? = nil, recordingID: String? = nil, isrc: String? = nil) {
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.title = title
        self.artist = artist
        self.artistIDs = artistIDs
        self.durationMs = durationMs
        self.recordingID = recordingID
        self.isrc = isrc
    }
}

/// 앨범(릴리스) 후보. `tracks`는 상세 조회 후에만 채워진다.
public struct ReleaseCandidate: Codable, Hashable, Sendable, Identifiable {
    public var source: ProviderID
    public var id: String
    public var releaseGroupID: String?
    public var title: String
    public var artist: String
    public var artistIDs: [String]
    /// 최초 발매일 (릴리스 그룹 기준이 있으면 그것)
    public var date: String?
    public var primaryType: String?
    public var secondaryTypes: [String]
    public var trackCount: Int
    public var discCount: Int
    public var artworkURL: URL?
    public var genre: String?
    public var tracks: [ReleaseTrack]?

    public init(source: ProviderID, id: String, releaseGroupID: String? = nil, title: String, artist: String,
                artistIDs: [String] = [], date: String? = nil, primaryType: String? = nil, secondaryTypes: [String] = [],
                trackCount: Int = 0, discCount: Int = 1, artworkURL: URL? = nil, genre: String? = nil,
                tracks: [ReleaseTrack]? = nil) {
        self.source = source
        self.id = id
        self.releaseGroupID = releaseGroupID
        self.title = title
        self.artist = artist
        self.artistIDs = artistIDs
        self.date = date
        self.primaryType = primaryType
        self.secondaryTypes = secondaryTypes
        self.trackCount = trackCount
        self.discCount = discCount
        self.artworkURL = artworkURL
        self.genre = genre
        self.tracks = tracks
    }

    public static let variousArtistsMBID = "89ad4ac3-39f7-470e-963a-56509c546377"

    public var isVariousArtists: Bool {
        artistIDs.contains(Self.variousArtistsMBID) || Normalizer.matchKey(artist) == "variousartists"
    }

    public var year: Int? { date.flatMap { Int($0.prefix(4)) } }

    /// 원 릴리스가 아닐 가능성이 큰 유형 (Phase 0: 컴필레이션·라이브·리믹스가 원 앨범보다 먼저 잡히는 문제)
    public var isSecondaryRelease: Bool {
        isVariousArtists || !Set(secondaryTypes).isDisjoint(with: ["Compilation", "Live", "Remix", "DJ-mix", "Mixtape/Street"])
    }
}

/// 녹음(곡) 후보
public struct RecordingCandidate: Hashable, Sendable {
    public struct Appearance: Hashable, Sendable {
        public var release: ReleaseCandidate
        public var discNumber: Int
        public var trackNumber: Int
    }

    public var source: ProviderID
    public var id: String
    public var title: String
    public var artist: String
    public var artistIDs: [String]
    public var durationMs: Int?
    public var isrc: String?
    public var appearances: [Appearance]
}

public struct ArtistMatch: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// 한글 표기 (MusicBrainz 한국어 별칭)
    public var koreanName: String?
}

/// 릴리스 선택 규칙 (Phase 0 검증):
/// ① 컴필레이션·라이브·리믹스·Various Artists 제외 → ② 한국 곡이면 한글 제목 우선 → ③ Album > EP > Single → ④ 최초 발매일.
/// 발매일을 유형보다 먼저 보면 선공개 싱글이 잡힌다.
public enum ReleasePreference {
    public static func isPreferred(_ lhs: ReleaseCandidate, over rhs: ReleaseCandidate, preferHangul: Bool) -> Bool {
        let a = key(lhs, preferHangul: preferHangul), b = key(rhs, preferHangul: preferHangul)
        if a.0 != b.0 { return a.0 < b.0 }
        if a.1 != b.1 { return a.1 < b.1 }
        if a.2 != b.2 { return a.2 < b.2 }
        return a.3 < b.3
    }

    public static func sorted(_ releases: [ReleaseCandidate], preferHangul: Bool) -> [ReleaseCandidate] {
        releases.sorted { isPreferred($0, over: $1, preferHangul: preferHangul) }
    }

    private static func key(_ release: ReleaseCandidate, preferHangul: Bool) -> (Int, Int, Int, String) {
        let typeRank = ["Album": 0, "EP": 1, "Single": 2][release.primaryType ?? ""] ?? 3
        return (release.isSecondaryRelease ? 1 : 0,
                preferHangul && !Normalizer.containsHangul(release.title) ? 1 : 0,
                typeRank,
                release.date ?? "9999")
    }
}
