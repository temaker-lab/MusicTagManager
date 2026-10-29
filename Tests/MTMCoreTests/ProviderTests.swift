import XCTest
@testable import MTMCore

final class ProviderTests: XCTestCase {
    override func setUp() {
        MockURLProtocol.install(flowerBookmarkRouter)
    }

    func testResolveKoreanArtistThroughAlias() async throws {
        let (_, musicBrainz, _) = makeProviders()
        let artist = try await musicBrainz.resolveArtist(named: "아이유(IU)")
        XCTAssertEqual(artist?.id, "b9545342-1e6d-4dae-84ac-013374ad8d7c")
        XCTAssertEqual(artist?.name, "IU")
        XCTAssertEqual(artist?.koreanName, "아이유")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MusicTagManager/0.1 ( test@example.com )")
        XCTAssertTrue(request.url!.absoluteString.contains("fmt=json"))
    }

    /// 실측: ‘별’ 검색에서 별칭이 ‘별’인 그룹(모임 별, 100점)보다 이름이 정확히 ‘별’인 가수(76점)를 먼저 고른다
    func testExactArtistNameBeatsAliasAndScore() async throws {
        MockURLProtocol.install { _ in (200, fixture("mb_artist_search_byul")) }
        let (_, musicBrainz, _) = makeProviders()
        let artists = try await musicBrainz.resolveArtists(named: "별")
        XCTAssertEqual(artists.first?.id, "7c13311c-5235-4022-b2f1-6860d0c70873", "가수 별")
        XCTAssertEqual(artists.dropFirst().first?.id, "bb091494-8742-4ea8-b6ae-1e014510e745", "별칭이 같은 모임 별은 다음 후보")
    }

    /// 이름이 다른 아티스트(예: ‘Star’ → Big Star)는 점수가 100이어도 고르지 않는다
    func testDifferentArtistNameIsNotChosenByScore() async throws {
        MockURLProtocol.install { _ in (200, fixture("mb_artist_search_star")) }
        let (_, musicBrainz, _) = makeProviders()
        let artists = try await musicBrainz.resolveArtists(named: "Star")
        XCTAssertFalse(artists.contains { $0.name == "Big Star" })
    }

    /// ‘+’가 공백으로 읽히지 않게 %2B로 보낸다 (실측: ‘2+1’ 검색이 ‘2 1’이 되어 못 찾음)
    func testPlusSignIsPercentEncoded() async throws {
        MockURLProtocol.install { _ in (200, Data(#"{"recordings":[]}"#.utf8)) }
        let (_, musicBrainz, itunes) = makeProviders()
        _ = try await musicBrainz.searchRecordings(title: "2+1", artistID: nil)
        _ = try? await itunes.searchAlbums(term: "2+1")
        let urls = MockURLProtocol.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(urls.allSatisfy { $0.contains("2%2B1") && !$0.contains("2+1") }, "\(urls)")
    }

    func testReleaseLookupBuildsTracklistAndCoverArt() async throws {
        let (_, musicBrainz, _) = makeProviders()
        let release = try await musicBrainz.release(id: "21b2d187-b7c5-4409-9621-085874d947d7")
        XCTAssertEqual(release.title, "꽃갈피 둘")
        XCTAssertEqual(release.primaryType, "EP")
        XCTAssertEqual(release.date, "2017-09-22")
        XCTAssertEqual(release.trackCount, 6)
        XCTAssertEqual(release.tracks?.map(\.trackNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(release.tracks?.first?.title, "가을 아침")
        XCTAssertEqual(release.tracks?.first?.isrc, "KRA381702215")
        XCTAssertEqual(release.artworkURL?.absoluteString,
                       "https://coverartarchive.org/release/21b2d187-b7c5-4409-9621-085874d947d7/front-1200")
        XCTAssertFalse(release.isSecondaryRelease)
    }

    func testRecordingSearchListsAppearances() async throws {
        let (_, musicBrainz, _) = makeProviders()
        let recordings = try await musicBrainz.searchRecordings(title: "가을 아침", artistID: "b9545342")
        let first = try XCTUnwrap(recordings.first)
        XCTAssertEqual(first.title, "가을 아침")
        XCTAssertTrue(first.appearances.contains { $0.release.title == "꽃갈피 둘" && $0.trackNumber == 1 })
        let compilation = try XCTUnwrap(first.appearances.first { $0.release.title.hasPrefix("Smash Hits 2") })
        XCTAssertTrue(compilation.release.isSecondaryRelease)
        XCTAssertEqual(compilation.trackNumber, 10)
    }

    func testDurationFilterIsAddedWhenArtistUnknown() async throws {
        let (_, musicBrainz, _) = makeProviders()
        _ = try await musicBrainz.searchRecordings(title: "가을 아침", artistID: nil, durationMs: 218_000)
        let query = MockURLProtocol.requests.last?.url?.query(percentEncoded: false) ?? ""
        XCTAssertTrue(query.contains("dur:[215000 TO 221000]"), query)
    }

    func testITunesAlbumUsesUSStoreAndLargeArtwork() async throws {
        let (_, _, itunes) = makeProviders()
        let albums = try await itunes.searchAlbums(term: "아이유 꽃갈피 둘")
        let flower = try XCTUnwrap(albums.first { $0.id == "1288487936" })
        XCTAssertEqual(flower.title, "A Flower Bookmark, Pt. 2")
        XCTAssertEqual(flower.primaryType, "EP")
        XCTAssertTrue(flower.artworkURL!.absoluteString.contains("1200x1200bb"))
        XCTAssertTrue(MockURLProtocol.requests.last!.url!.absoluteString.contains("country=US"))

        let album = try await itunes.album(id: "1288487936")
        XCTAssertEqual(album.tracks?.count, 6)
        XCTAssertEqual(album.tracks?.first?.durationMs, 218_885)
    }

    func testAcoustIDMetadataBecomesRecordingCandidates() throws {
        let matches = try AcoustIDProvider.parse(fixture("acoustid_lookup_meta_autumn_morning"))
        let first = try XCTUnwrap(matches.first)
        XCTAssertEqual(first.recordingID, "a0145a34-a529-4936-9ec8-65888bd60e65")
        XCTAssertGreaterThan(first.score, 0.99)
        let recording = try XCTUnwrap(first.recording)
        XCTAssertEqual(recording.title, "가을 아침")
        XCTAssertEqual(recording.artist, "IU")
        let ep = try XCTUnwrap(recording.appearances.first { $0.release.title == "꽃갈피 둘" })
        XCTAssertEqual(ep.release.primaryType, "EP")
        XCTAssertEqual(ep.release.date, "2017-09-22")
        XCTAssertEqual(ep.trackNumber, 1)
        XCTAssertTrue(recording.appearances.contains { $0.release.isSecondaryRelease })
        // 메타데이터 없이 ID만 온 응답도 처리
        XCTAssertNil(try AcoustIDProvider.parse(fixture("acoustid_lookup_autumn_morning")).first?.recording)
    }

    func testAcoustIDErrorStatusThrows() {
        let data = Data(#"{"status":"error","error":{"message":"invalid API key"}}"#.utf8)
        XCTAssertThrowsError(try AcoustIDProvider.parse(data))
    }
}

final class HTTPClientTests: XCTestCase {
    func testRetriesTransientStatusThenSucceeds() async throws {
        let counter = Counter()
        MockURLProtocol.install { _ in counter.next() == 0 ? (503, Data()) : (200, Data("ok".utf8)) }
        let http = HTTPClient(session: MockURLProtocol.session(), cache: nil, baseBackoff: 0.01)
        let data = try await http.data(for: URLRequest(url: URL(string: "https://example.com/a")!), provider: "test",
                                       limiter: RateLimiter(interval: 0))
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testNonRetryableStatusThrows() async {
        MockURLProtocol.install { _ in (404, Data()) }
        let http = HTTPClient(session: MockURLProtocol.session(), cache: nil, baseBackoff: 0.01)
        do {
            _ = try await http.data(for: URLRequest(url: URL(string: "https://example.com/a")!), provider: "test",
                                    limiter: RateLimiter(interval: 0))
            XCTFail("404는 예외여야 함")
        } catch {
            XCTAssertEqual(error as? HTTPError, .status(404))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testGivesUpAfterMaxAttempts() async {
        MockURLProtocol.install { _ in (429, Data()) }
        let http = HTTPClient(session: MockURLProtocol.session(), cache: nil, maxAttempts: 3, baseBackoff: 0.01)
        do {
            _ = try await http.data(for: URLRequest(url: URL(string: "https://example.com/a")!), provider: "test",
                                    limiter: RateLimiter(interval: 0))
            XCTFail()
        } catch {
            XCTAssertEqual(error as? HTTPError, .retriesExhausted(429))
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    func testCachedResponseSkipsNetwork() async throws {
        MockURLProtocol.install { _ in (200, Data("fresh".utf8)) }
        let cache = ResponseCache(database: try AppDatabase.inMemory())
        let http = HTTPClient(session: MockURLProtocol.session(), cache: cache, baseBackoff: 0.01)
        let request = URLRequest(url: URL(string: "https://example.com/cached")!)
        _ = try await http.data(for: request, provider: "test", limiter: RateLimiter(interval: 0))
        let again = try await http.data(for: request, provider: "test", limiter: RateLimiter(interval: 0))
        XCTAssertEqual(String(data: again, encoding: .utf8), "fresh")
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        // 만료된 캐시는 쓰지 않는다
        XCTAssertNil(try cache.get("https://example.com/cached", maxAge: -1))
    }

    func testRateLimiterSpacesRequests() async {
        let limiter = RateLimiter(interval: 0.15)
        let start = Date()
        for _ in 0..<3 { await limiter.acquire() }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.29)
    }

    func testRateLimiterSpacesConcurrentRequests() async {
        let limiter = RateLimiter(interval: 0.1)
        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { await limiter.acquire() } }
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.29)
    }
}

final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}
