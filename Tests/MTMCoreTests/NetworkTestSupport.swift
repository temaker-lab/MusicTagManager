import Foundation
@testable import MTMCore

/// 실제 네트워크 대신 Fixtures/의 응답을 돌려주는 URLProtocol
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, data: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            recorded = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { recorded } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded.append(request)
            return Self.handler
        }
        let (status, data) = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

/// IU 「꽃갈피 둘」 시나리오 (MusicBrainz + iTunes 응답)
let flowerBookmarkRouter: MockURLProtocol.Handler = { request in
    let url = request.url!
    switch (url.host ?? "", url.path) {
    case ("musicbrainz.org", "/ws/2/artist"): return (200, fixture("mb_artist_search_iu"))
    case ("musicbrainz.org", "/ws/2/release"): return (200, fixture("mb_release_search_flower2"))
    case ("musicbrainz.org", let path) where path.hasPrefix("/ws/2/release/"): return (200, fixture("mb_release_flower2"))
    case ("musicbrainz.org", "/ws/2/recording"): return (200, fixture("mb_recording_search_autumn_morning"))
    case ("musicbrainz.org", let path) where path.hasPrefix("/ws/2/recording/"): return (200, fixture("mb_recording_autumn_morning"))
    case ("itunes.apple.com", "/search"): return (200, fixture("itunes_album_search_flower2"))
    case ("itunes.apple.com", "/lookup"): return (200, fixture("itunes_lookup_flower2"))
    default: return (404, Data())
    }
}

/// 테스트용: 대기 없는 리미터와 짧은 백오프
func makeProviders(cache: ResponseCache? = nil) -> (HTTPClient, MusicBrainzProvider, ITunesSearchProvider) {
    let http = HTTPClient(session: MockURLProtocol.session(), cache: cache, baseBackoff: 0.01)
    return (http,
            MusicBrainzProvider(http: http, contact: "test@example.com", limiter: RateLimiter(interval: 0)),
            ITunesSearchProvider(http: http, limiter: RateLimiter(interval: 0)))
}
