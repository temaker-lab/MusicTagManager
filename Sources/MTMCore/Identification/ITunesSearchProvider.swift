import Foundation

/// iTunes Search API. 커버(1200×1200)와 교차 확인용.
/// `country=KR`은 음원을 반환하지 않으므로(Phase 0) 기본 US 스토어를 쓴다. 한국 곡은 영문 표기로 나온다.
public final class ITunesSearchProvider: Sendable {
    private let http: HTTPClient
    private let limiter: RateLimiter
    private let country: String

    /// 분당 약 20회
    public init(http: HTTPClient, country: String = "US", limiter: RateLimiter = RateLimiter(interval: 3.1)) {
        self.http = http
        self.country = country
        self.limiter = limiter
    }

    public func searchAlbums(term: String) async throws -> [ReleaseCandidate] {
        let response: ITunesResponse = try await get("search", ["term": term, "entity": "album", "limit": "10"])
        return response.results.filter { $0.wrapperType == "collection" }.map(Self.release)
    }

    /// 노래 단위 검색 (지문·MusicBrainz 실패 시 텍스트 폴백). 곡이 실린 앨범 ID와 트랙 위치를 돌려준다.
    public func searchSongs(term: String) async throws -> [ITunesSongMatch] {
        let response: ITunesResponse = try await get("search", ["term": term, "entity": "song", "limit": "15"])
        return response.results.filter { $0.wrapperType == "track" }.compactMap { item in
            guard let id = item.collectionId, let name = item.trackName else { return nil }
            return ITunesSongMatch(collectionID: String(id), trackNumber: item.trackNumber ?? 0,
                                   discNumber: item.discNumber ?? 1, title: name,
                                   artist: item.artistName ?? "", durationMs: item.trackTimeMillis)
        }
    }

    /// 노래 검색으로 이 곡이 실린 앨범의 커버(1200) URL을 찾는다. 커버 '지연 후보'(itunes-song:) 처리에 쓴다.
    /// 제목·버전·가수가 맞는 곡만 인정한다. 맞는 곡이 없으면 nil.
    public func songCoverURL(title: String, artist: String) async throws -> URL? {
        let term = [artist.isEmpty ? nil : artist, title].compactMap { $0 }.joined(separator: " ")
        let songs = try await searchSongs(term: term)
        guard let match = songs.first(where: { song in
            Normalizer.similarity(title, song.title) >= 0.85
                && Normalizer.versionTags(title) == Normalizer.versionTags(song.title)
                && (artist.isEmpty || Normalizer.artistSimilarity(artist, song.artist) >= 0.6)
        }) else { return nil }
        return try await album(id: match.collectionID).artworkURL
    }

    /// 앨범커버 검색 전용: 썸네일(300)과 원본(1200) URL을 함께 돌려준다.
    public func searchCovers(term: String) async throws -> [AlbumCoverCandidate] {
        let response: ITunesResponse = try await get("search", ["term": term, "entity": "album", "limit": "12"])
        return response.results.filter { $0.wrapperType == "collection" }.compactMap { item in
            guard let raw = item.artworkUrl100, let id = item.collectionId,
                  let full = URL(string: raw.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")) else { return nil }
            let thumb = URL(string: raw.replacingOccurrences(of: "100x100bb", with: "300x300bb")) ?? full
            return AlbumCoverCandidate(id: "itunes:\(id)", source: .itunes, thumbnailURL: thumb, imageURL: full,
                                       albumTitle: item.collectionName ?? "", artist: item.artistName ?? "")
        }
    }

    /// 트랙리스트 포함 앨범
    public func album(id: String) async throws -> ReleaseCandidate {
        let response: ITunesResponse = try await get("lookup", ["id": id, "entity": "song"])
        guard let collection = response.results.first(where: { $0.wrapperType == "collection" }) else {
            throw HTTPError.status(404)
        }
        var release = Self.release(collection)
        release.tracks = response.results.filter { $0.wrapperType == "track" }.map { track in
            ReleaseTrack(discNumber: track.discNumber ?? 1, trackNumber: track.trackNumber ?? 0, title: track.trackName ?? "",
                         artist: track.artistName ?? "", durationMs: track.trackTimeMillis,
                         recordingID: track.trackId.map(String.init))
        }
        release.discCount = max(release.discCount, release.tracks?.map(\.discNumber).max() ?? 1)
        return release
    }

    static func release(_ item: ITunesItem) -> ReleaseCandidate {
        var title = item.collectionName ?? ""
        var type = "Album"
        for (suffix, kind) in [(" - Single", "Single"), (" - EP", "EP")] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
            type = kind
        }
        let artwork = item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")) }
        return ReleaseCandidate(
            source: .itunes, id: item.collectionId.map(String.init) ?? "", title: title, artist: item.artistName ?? "",
            date: item.releaseDate.map { String($0.prefix(10)) }, primaryType: type,
            secondaryTypes: item.artistName == "Various Artists" ? ["Compilation"] : [],
            trackCount: item.trackCount ?? 0, discCount: item.discCount ?? 1, artworkURL: artwork, genre: item.primaryGenreName)
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(string: "https://itunes.apple.com/\(path)")!
        components.queryItems = (query.merging(["country": country]) { a, _ in a })
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // ‘+’는 쿼리에서 공백으로 읽히므로 따로 인코딩한다 (실측: ‘2+1’이 ‘2 1’로 검색되어 못 찾음)
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let request = URLRequest(url: components.url!)
        // iTunes는 과도한 요청에 403을 주기도 한다
        let data = try await http.data(for: request, provider: ProviderID.itunes.rawValue, limiter: limiter,
                                       retryStatuses: [403, 429, 500, 502, 503, 504])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// iTunes 노래 검색에서 고른 한 곡 (앨범 조회·트랙 매칭용)
public struct ITunesSongMatch: Sendable {
    public let collectionID: String
    public let trackNumber: Int
    public let discNumber: Int
    public let title: String
    public let artist: String
    public let durationMs: Int?
}

struct ITunesItem: Decodable, Sendable {
    let wrapperType: String?
    let collectionId: Int?
    let collectionName: String?
    let artistName: String?
    let trackId: Int?
    let trackName: String?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
    let trackTimeMillis: Int?
    let releaseDate: String?
    let primaryGenreName: String?
    let artworkUrl100: String?
}

struct ITunesResponse: Decodable {
    let results: [ITunesItem]
}
