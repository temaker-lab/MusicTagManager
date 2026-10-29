import Foundation

/// 앨범커버 검색 결과 하나 (미리보기용 썸네일과 저장용 원본 URL)
public struct AlbumCoverCandidate: Sendable, Hashable, Identifiable {
    public let id: String
    public let source: ProviderID
    public let thumbnailURL: URL
    public let imageURL: URL
    public let albumTitle: String
    public let artist: String

    public init(id: String, source: ProviderID, thumbnailURL: URL, imageURL: URL, albumTitle: String, artist: String) {
        self.id = id
        self.source = source
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
        self.albumTitle = albumTitle
        self.artist = artist
    }
}

/// 곡 정보로 앨범커버를 찾는다. iTunes를 먼저 쓰고 결과가 없으면 Deezer로 보충한다.
public final class AlbumCoverService: Sendable {
    private let itunes: ITunesSearchProvider
    private let deezer: DeezerProvider

    public init(http: HTTPClient, itunesCountry: String = "US") {
        itunes = ITunesSearchProvider(http: http, country: itunesCountry)
        deezer = DeezerProvider(http: http)
    }

    /// 입력된 값(제목·가수·앨범)만으로 검색어를 만들어 커버를 찾는다. 하나도 없으면 빈 배열.
    public func search(title: String, artist: String, album: String) async -> [AlbumCoverCandidate] {
        let term = Self.term(title: title, artist: artist, album: album)
        guard !term.isEmpty else { return [] }
        let itunesCovers = (try? await itunes.searchCovers(term: term)) ?? []
        if !itunesCovers.isEmpty { return itunesCovers }
        return (try? await deezer.searchCovers(term: term)) ?? []
    }

    /// 앨범 커버는 보통 가수 + 앨범명으로 가장 잘 찾는다. 앨범명이 없으면 곡 제목으로 대신한다.
    static func term(title: String, artist: String, album: String) -> String {
        let artist = Normalizer.clean(artist)
        let album = Normalizer.clean(album)
        let title = Normalizer.clean(title)
        let core = album.isEmpty ? title : album
        return [artist, core].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Deezer 공개 검색 API. 키가 필요 없고 커버를 여러 해상도로 돌려준다.
public final class DeezerProvider: Sendable {
    private let http: HTTPClient
    private let limiter: RateLimiter

    public init(http: HTTPClient, limiter: RateLimiter = RateLimiter(interval: 0.5)) {
        self.http = http
        self.limiter = limiter
    }

    public func searchCovers(term: String) async throws -> [AlbumCoverCandidate] {
        var components = URLComponents(string: "https://api.deezer.com/search/album")!
        components.queryItems = [URLQueryItem(name: "q", value: term), URLQueryItem(name: "limit", value: "12")]
        let request = URLRequest(url: components.url!)
        let data = try await http.data(for: request, provider: ProviderID.deezer.rawValue, limiter: limiter)
        let response = try JSONDecoder().decode(DeezerSearch.self, from: data)
        return response.data.compactMap { album in
            guard let full = URL(string: album.coverXl ?? album.coverBig ?? "") else { return nil }
            let thumb = URL(string: album.coverMedium ?? album.coverBig ?? "") ?? full
            return AlbumCoverCandidate(id: "deezer:\(album.id)", source: .deezer, thumbnailURL: thumb, imageURL: full,
                                       albumTitle: album.title, artist: album.artist?.name ?? "")
        }
    }
}

struct DeezerSearch: Decodable { let data: [DeezerAlbum] }

struct DeezerAlbum: Decodable {
    let id: Int
    let title: String
    let coverMedium: String?
    let coverBig: String?
    let coverXl: String?
    let artist: DeezerArtist?

    enum CodingKeys: String, CodingKey {
        case id, title, artist
        case coverMedium = "cover_medium"
        case coverBig = "cover_big"
        case coverXl = "cover_xl"
    }
}

struct DeezerArtist: Decodable { let name: String }
