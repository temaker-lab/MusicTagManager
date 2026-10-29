import Foundation

/// MusicBrainz Web Service v2. 초당 1회 이하, 연락처가 담긴 User-Agent 필수.
public final class MusicBrainzProvider: Sendable {
    static let baseURL = URL(string: "https://musicbrainz.org/ws/2/")!

    private let http: HTTPClient
    private let limiter: RateLimiter
    private let userAgent: String

    public init(http: HTTPClient, contact: String, appVersion: String = "0.1",
                limiter: RateLimiter = RateLimiter(interval: 1.1)) {
        self.http = http
        self.limiter = limiter
        self.userAgent = "MusicTagManager/\(appVersion) ( \(contact) )"
    }

    // MARK: - 아티스트

    /// 별칭 색인으로 아티스트를 찾는다. MusicBrainz는 한국 가수를 영문 크레딧(`IU`)으로 두므로
    /// 한글 이름(`아이유`)으로 녹음을 바로 검색하면 실패한다(Phase 0).
    public func resolveArtist(named name: String) async throws -> ArtistMatch? {
        try await resolveArtists(named: name).first
    }

    /// 이름이 맞는 아티스트 후보 (맞을 가능성이 큰 순서).
    /// ① 이름이 정확히 같은 아티스트(검색 점수와 무관) → ② 별칭이 같은 아티스트 → ③ 점수 100이면서 이름이 비슷한 아티스트.
    /// (실측: ‘별’ 검색 시 별칭이 ‘별’인 그룹 ‘모임 별’이 100점, 가수 ‘별’은 76점으로 나와 엉뚱한 아티스트로 검색했었다)
    public func resolveArtists(named name: String) async throws -> [ArtistMatch] {
        for variant in Normalizer.artistNameVariants(name) {
            let response: MBArtistSearch = try await get("artist", [
                "query": "artist:\(phrase(variant)) OR alias:\(phrase(variant))", "limit": "5",
            ])
            let key = Normalizer.matchKey(variant)
            let all = response.artists
            let byName = all.filter { ($0.score ?? 0) >= 50 && Normalizer.matchKey($0.name) == key }
            let byAlias = all.filter { artist in
                (artist.score ?? 0) >= 90 && !byName.contains { $0.id == artist.id }
                    && (artist.aliases ?? []).contains { Normalizer.matchKey($0.name) == key }
            }
            var ordered = byName + byAlias
            if ordered.isEmpty {
                ordered = all.filter { ($0.score ?? 0) == 100 && Normalizer.artistSimilarity(variant, $0.name) >= 0.85 }
            }
            guard !ordered.isEmpty else { continue }
            return ordered.map { ArtistMatch(id: $0.id, name: $0.name, koreanName: Self.koreanName(of: $0)) }
        }
        return []
    }

    /// 한국 가수의 한글 표기. 외국 가수의 한글 별칭(예: 러시아 가수의 음역)은 쓰지 않는다.
    static func koreanName(of artist: MBArtist) -> String? {
        if Normalizer.containsHangul(artist.name) { return artist.name }
        guard artist.country == "KR" else { return nil }
        let aliases = (artist.aliases ?? []).filter { Normalizer.containsHangul($0.name) && $0.type != "Legal name" }
        return (aliases.first { $0.locale == "ko" && $0.primary == true } ?? aliases.first { $0.locale == "ko" } ?? aliases.first)?.name
    }

    // MARK: - 검색

    public func searchReleases(title: String, artistID: String?) async throws -> [ReleaseCandidate] {
        var query = "release:\(phrase(title))"
        if let artistID { query += " AND arid:\(artistID)" }
        let response: MBReleaseSearch = try await get("release", ["query": query, "limit": "15"])
        return response.releases.map { Self.candidate(from: $0) }
    }

    /// - Parameter durationMs: 가수를 모를 때 길이(±3초)로 후보를 좁힌다
    public func searchRecordings(title: String, artistID: String?, durationMs: Int? = nil) async throws -> [RecordingCandidate] {
        var query = "recording:\(phrase(title))"
        if let artistID { query += " AND arid:\(artistID)" }
        if let durationMs, durationMs > 0 { query += " AND dur:[\(max(0, durationMs - 3_000)) TO \(durationMs + 3_000)]" }
        let response: MBRecordingSearch = try await get("recording", ["query": query, "limit": "15"])
        return response.recordings.map { Self.candidate(from: $0) }
    }

    // MARK: - 상세 조회

    /// 트랙리스트 포함 릴리스
    public func release(id: String) async throws -> ReleaseCandidate {
        let release: MBRelease = try await get("release/\(id)", ["inc": "recordings+artist-credits+release-groups+isrcs"])
        return Self.candidate(from: release, includeTracks: true)
    }

    /// 지문으로 얻은 녹음 ID → 녹음과 수록 릴리스·위치
    public func recording(id: String) async throws -> RecordingCandidate {
        let recording: MBRecording = try await get("recording/\(id)", ["inc": "releases+release-groups+artist-credits+isrcs+media"])
        return Self.candidate(from: recording)
    }

    // MARK: - 변환

    static func candidate(from release: MBRelease, includeTracks: Bool = false) -> ReleaseCandidate {
        let media = release.media ?? []
        var tracks: [ReleaseTrack]?
        if includeTracks {
            tracks = media.enumerated().flatMap { offset, medium in
                (medium.tracks ?? medium.track ?? []).map { track in
                    let credit = track.artistCredit ?? track.recording?.artistCredit ?? release.artistCredit ?? []
                    return ReleaseTrack(
                        discNumber: medium.position ?? offset + 1,
                        trackNumber: track.position ?? Int(track.number ?? "") ?? 0,
                        title: track.title ?? track.recording?.title ?? "",
                        artist: creditName(credit), artistIDs: credit.map(\.artist.id),
                        durationMs: track.length ?? track.recording?.length,
                        recordingID: track.recording?.id, isrc: track.recording?.isrcs?.first)
                }
            }
        }
        let credit = release.artistCredit ?? []
        let artwork = release.coverArtArchive?.front == true
            ? URL(string: "https://coverartarchive.org/release/\(release.id)/front-1200") : nil
        return ReleaseCandidate(
            source: .musicbrainz, id: release.id, releaseGroupID: release.releaseGroup?.id, title: release.title,
            artist: creditName(credit), artistIDs: credit.map(\.artist.id),
            date: release.releaseGroup?.firstReleaseDate.flatMap { $0.isEmpty ? nil : $0 } ?? release.date,
            primaryType: release.releaseGroup?.primaryType, secondaryTypes: release.releaseGroup?.secondaryTypes ?? [],
            trackCount: release.trackCount ?? media.reduce(0) { $0 + ($1.trackCount ?? 0) },
            discCount: max(1, media.count), artworkURL: artwork, tracks: tracks)
    }

    static func candidate(from recording: MBRecording) -> RecordingCandidate {
        let credit = recording.artistCredit ?? []
        let appearances = (recording.releases ?? []).compactMap { release -> RecordingCandidate.Appearance? in
            guard let medium = release.media?.first else { return nil }
            let track = (medium.tracks ?? medium.track ?? []).first
            let number = track?.position ?? Int(track?.number ?? "") ?? 0
            return RecordingCandidate.Appearance(release: candidate(from: release), discNumber: medium.position ?? 1, trackNumber: number)
        }
        return RecordingCandidate(source: .musicbrainz, id: recording.id, title: recording.title, artist: creditName(credit),
                                  artistIDs: credit.map(\.artist.id), durationMs: recording.length,
                                  isrc: recording.isrcs?.first, appearances: appearances)
    }

    static func creditName(_ credit: [MBArtistCredit]) -> String {
        credit.map { $0.name + ($0.joinphrase ?? "") }.joined()
    }

    // MARK: - HTTP

    /// Lucene 구문 검색어: 따옴표로 묶고 내부 따옴표·역슬래시만 이스케이프
    private func phrase(_ value: String) -> String {
        "\"" + Normalizer.clean(value).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "fmt", value: "json")]
        // ‘+’는 쿼리에서 공백으로 읽히므로 따로 인코딩한다 (실측: ‘2+1’이 ‘2 1’로 검색되어 못 찾음)
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await http.data(for: request, provider: ProviderID.musicbrainz.rawValue, limiter: limiter)
        return try JSONDecoder.kebabCase.decode(T.self, from: data)
    }
}

// MARK: - 응답 모델 (필요한 필드만)

struct MBArtistCredit: Decodable, Sendable {
    struct Artist: Decodable, Sendable { let id: String; let name: String }
    let name: String
    let joinphrase: String?
    let artist: Artist
}

struct MBAlias: Decodable, Sendable {
    let name: String
    let locale: String?
    let primary: Bool?
    let type: String?
}

struct MBArtist: Decodable, Sendable {
    let id: String
    let name: String
    let country: String?
    let score: Int?
    let aliases: [MBAlias]?
}

struct MBReleaseGroup: Decodable, Sendable {
    let id: String?
    let primaryType: String?
    let secondaryTypes: [String]?
    let firstReleaseDate: String?
}

struct MBRecordingRef: Decodable, Sendable {
    let id: String
    let title: String?
    let length: Int?
    let isrcs: [String]?
    let artistCredit: [MBArtistCredit]?
}

struct MBTrack: Decodable, Sendable {
    let number: String?
    let position: Int?
    let title: String?
    let length: Int?
    let recording: MBRecordingRef?
    let artistCredit: [MBArtistCredit]?
}

struct MBMedium: Decodable, Sendable {
    let position: Int?
    let trackCount: Int?
    /// 상세 조회는 `tracks`, 검색 결과는 `track`
    let tracks: [MBTrack]?
    let track: [MBTrack]?
}

struct MBRelease: Decodable, Sendable {
    struct CoverArt: Decodable, Sendable { let front: Bool? }
    let id: String
    let title: String
    let date: String?
    let trackCount: Int?
    let artistCredit: [MBArtistCredit]?
    let releaseGroup: MBReleaseGroup?
    let media: [MBMedium]?
    let coverArtArchive: CoverArt?
}

struct MBRecording: Decodable, Sendable {
    let id: String
    let title: String
    let length: Int?
    let isrcs: [String]?
    let artistCredit: [MBArtistCredit]?
    let releases: [MBRelease]?
}

struct MBArtistSearch: Decodable { let artists: [MBArtist] }
struct MBReleaseSearch: Decodable { let releases: [MBRelease] }
struct MBRecordingSearch: Decodable { let recordings: [MBRecording] }

extension JSONDecoder {
    /// MusicBrainz 키 형식(`release-group`, `first-release-date`) → camelCase
    static let kebabCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let raw = keys.last!.stringValue
            let parts = raw.split(separator: "-")
            let camel = parts.enumerated().map { $0 == 0 ? String($1) : $1.prefix(1).uppercased() + $1.dropFirst() }.joined()
            return AnyKey(camel)
        }
        return decoder
    }()
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
