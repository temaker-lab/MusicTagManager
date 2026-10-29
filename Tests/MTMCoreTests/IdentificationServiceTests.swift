import XCTest
@testable import MTMCore

/// 「꽃갈피 둘」 픽스처로 앨범 단위 식별 전체 흐름 확인 (지문 없음)
final class IdentificationServiceTests: XCTestCase {
    private let titles = ["가을 아침", "비밀의 화원", "잠 못 드는 밤 비는 내리고", "어젯밤 이야기", "개여울", "매일 그대와"]
    private let durations = [218_500, 224_400, 266_200, 233_300, 337_100, 224_600]

    override func setUp() {
        MockURLProtocol.install(flowerBookmarkRouter)
    }

    /// 1·2번 곡은 커버 없음(대상), 3~6번은 완비(참고)
    private func scope(mutate: (inout [LibraryTrack]) -> Void = { _ in }) -> [EvaluatedTrack] {
        var tracks = titles.indices.map { i in
            LibraryTrack(id: pid(UInt64(i + 1)), title: titles[i], artist: "아이유", album: "꽃갈피 둘",
                         trackNumber: i + 1, durationMs: durations[i], hasArtwork: i >= 2,
                         fileURL: URL(fileURLWithPath: "/Music/아이유/꽃갈피 둘/\(i + 1).mp3"),
                         modifiedDate: Date(timeIntervalSince1970: 1_700_000_000))
        }
        mutate(&tracks)
        let checker = CompletenessChecker()
        return tracks.map { EvaluatedTrack(track: $0, result: checker.evaluate($0, fileExists: alwaysExists)) }
    }

    private func makeService(_ database: AppDatabase) -> IdentificationService {
        let (_, musicBrainz, itunes) = makeProviders()
        return IdentificationService(database: database, musicBrainz: musicBrainz, itunes: itunes, acoustID: nil)
    }

    func testAlbumGroupResolvesToOneReleaseAndScoresEvidence() async throws {
        let database = try AppDatabase.inMemory()
        let summary = try await makeService(database).identify(scope: scope())
        XCTAssertEqual(summary.groups, 1)
        XCTAssertEqual(summary.tracks, 2)

        let proposals = try database.proposals().sorted { $0.persistentID < $1.persistentID }
        XCTAssertEqual(proposals.map(\.persistentID), [pid(1).hex, pid(2).hex])
        let first = proposals[0]
        XCTAssertEqual(first.externalReleaseID, "21b2d187-b7c5-4409-9621-085874d947d7")
        XCTAssertEqual(first.title, "가을 아침")
        XCTAssertEqual(first.artist, "아이유", "같은 앨범 곡에 쓰인 기존 표기를 따른다")
        XCTAssertEqual(first.album, "꽃갈피 둘")
        XCTAssertEqual(first.trackNo, 1)
        XCTAssertEqual(first.trackCount, 6)
        XCTAssertEqual(first.year, 2017)
        XCTAssertEqual(first.genre, "K-Pop")
        // 같은 앨범 곡의 기존 커버가 1순위, 그다음 iTunes, Cover Art Archive
        XCTAssertEqual(first.artworkRef, "track:\(pid(3).hex)")
        XCTAssertTrue(first.artworkCandidates.contains { $0.hasPrefix("itunes:") && $0.contains("1200x1200bb") })
        XCTAssertTrue(first.artworkCandidates.contains { $0.hasPrefix("caa:") })

        let evidence = try XCTUnwrap(first.evidence.match)
        XCTAssertEqual(evidence.titleSimilarity, 1)
        XCTAssertEqual(evidence.artistSimilarity, 1, "아이유 ↔ MusicBrainz 크레딧 IU (한글 별칭)")
        XCTAssertTrue(evidence.trackCountMatches)
        XCTAssertTrue(evidence.sourcesAgree, "iTunes 영문 앨범과 트랙 길이로 같은 앨범 확인")
        XCTAssertFalse(evidence.fingerprintMatched)
        // 제목 20 + 가수 15 + 앨범 10 + 길이 10 + 트랙 수 10 + 소스 일치 10 = 75 → 지문 없이는 검토 대기
        XCTAssertEqual(first.confidenceScore, 75)
        XCTAssertEqual(first.confidenceLevel, .medium)
        XCTAssertTrue(first.blocksAutoApply)
        XCTAssertEqual(first.decision, .pending)
        XCTAssertEqual(first.status(of: .artwork), .changed)
        XCTAssertEqual(first.status(of: .title), .unchanged)

        let album = try XCTUnwrap(try database.resolvedAlbums().first)
        XCTAssertEqual(album.title, "꽃갈피 둘")
        XCTAssertEqual(album.alternatives.count, 2)
    }

    func testSecondRunSkipsUnchangedTracks() async throws {
        let database = try AppDatabase.inMemory()
        let service = makeService(database)
        _ = try await service.identify(scope: scope())
        let requests = MockURLProtocol.requests.count
        let again = try await service.identify(scope: scope())
        XCTAssertEqual(again.groups, 0)
        XCTAssertEqual(MockURLProtocol.requests.count, requests)
        let forced = try await service.identify(scope: scope(), force: true)
        XCTAssertEqual(forced.groups, 1)
    }

    /// 사용자 요청: 되돌려서 거절된 곡도 식별을 다시 실행하면 검토 대기로 돌아온다
    func testRejectedDecisionResetsOnReidentification() async throws {
        let database = try AppDatabase.inMemory()
        let service = makeService(database)
        _ = try await service.identify(scope: scope())
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE proposals SET decision = 'REJECTED' WHERE persistent_id = ?", arguments: [pid(1).hex])
        }
        _ = try await service.identify(scope: scope(), force: true)
        XCTAssertEqual(try database.proposals().first { $0.persistentID == pid(1).hex }?.decision, .pending)
        XCTAssertEqual(try database.proposals().first { $0.persistentID == pid(2).hex }?.decision, .pending)
    }

    /// 앱 확인 결과: 식별을 다시 하면 그 시점 기준으로 상태가 초기화되어야 한다
    func testReidentificationResetsDecisionsButKeepsUserChoices() async throws {
        let database = try AppDatabase.inMemory()
        let service = makeService(database)
        _ = try await service.identify(scope: scope())
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE proposals SET decision = 'USER_APPROVED' WHERE persistent_id = ?", arguments: [pid(1).hex])
        }
        try database.saveOverride(persistentID: pid(2), albumGroupKey: "x", values: [.title: .text("직접 입력")],
                                  artworkFile: nil, keepArtworkCandidates: true)
        _ = try await service.identify(scope: scope(), force: true)
        let proposals = try database.proposals()
        XCTAssertEqual(proposals.first { $0.persistentID == pid(1).hex }?.decision, .pending)
        let override = proposals.first { $0.persistentID == pid(2).hex }
        XCTAssertEqual(override?.decision, .userOverride)
        XCTAssertEqual(override?.title, "직접 입력", "다시 식별해도 직접 입력한 값은 유지")

        // 정리 대상에서 빠진 곡은 결정과 관계없이 정리
        _ = try await service.identify(scope: scope { $0[0].hasArtwork = true; $0[1].hasArtwork = true })
        XCTAssertEqual(try database.proposals().count, 0)
    }

    func testCompletedTrackProposalIsPruned() async throws {
        let database = try AppDatabase.inMemory()
        let service = makeService(database)
        _ = try await service.identify(scope: scope())
        // 사용자가 Music에서 1번 곡 커버를 직접 넣음 → 더 이상 대상 아님
        _ = try await service.identify(scope: scope { $0[0].hasArtwork = true })
        XCTAssertEqual(try database.proposals().map(\.persistentID), [pid(2).hex])
    }

    func testEmptyTitleFilledFromTracklistByPosition() async throws {
        let database = try AppDatabase.inMemory()
        _ = try await makeService(database).identify(scope: scope { $0[1].title = "" })
        let proposal = try XCTUnwrap(try database.proposals().first { $0.persistentID == pid(2).hex })
        XCTAssertEqual(proposal.title, "비밀의 화원")
        XCTAssertEqual(proposal.status(of: .title), .changed)
        XCTAssertNil(proposal.evidence.match?.titleSimilarity, "비어 있던 제목은 근거로 쓰지 않는다")
    }

    func testExistingDifferentArtistIsFlaggedAndBlocked() async throws {
        let database = try AppDatabase.inMemory()
        _ = try await makeService(database).identify(scope: scope { tracks in
            for i in tracks.indices { tracks[i].artist = "전혀 다른 가수" }
        })
        let proposal = try XCTUnwrap(try database.proposals().first)
        XCTAssertEqual(proposal.evidence.match?.artistReplaced, true)
        XCTAssertTrue(proposal.blocksAutoApply)
    }

    /// 앨범명이 없는 단독 곡: 무엇을 시도했고 왜 못 찾았는지 남긴다
    private func unknownSingle() -> EvaluatedTrack {
        let track = LibraryTrack(id: pid(42), title: "zzqq 알수없는곡", artist: nil, album: nil, durationMs: 218_500,
                                 hasArtwork: false, fileURL: URL(fileURLWithPath: "/Music/x/zzqq.mp3"),
                                 modifiedDate: Date(timeIntervalSince1970: 1_700_000_000))
        return EvaluatedTrack(track: track, result: CompletenessChecker().evaluate(track, fileExists: alwaysExists))
    }

    func testUnidentifiedTrackRecordsFailureReasons() async throws {
        let database = try AppDatabase.inMemory()
        _ = try await makeService(database).identify(scope: [unknownSingle()])
        let proposal = try XCTUnwrap(try database.proposals().first)
        XCTAssertEqual(proposal.confidenceLevel, .none)
        let reasons = proposal.evidence.reasons.joined(separator: "\n")
        XCTAssertFalse(proposal.evidence.reasons.contains("후보 없음"), reasons)
        XCTAssertTrue(reasons.contains("오디오 지문 확인 안 함"), reasons)
        XCTAssertTrue(reasons.contains("MusicBrainz 검색 ‘zzqq 알수없는곡’"), reasons)
        XCTAssertTrue(reasons.contains("맞는 곡 없음"), reasons)
    }

    func testIdentifyWithHintsUsesEnteredValuesButKeepsRealBaseline() async throws {
        let database = try AppDatabase.inMemory()
        let service = makeService(database)
        let evaluated = unknownSingle()
        _ = try await service.identify(scope: [evaluated])
        let record = try await service.identifyWithHints(evaluated, title: "가을 아침", artist: "아이유", album: " ")
        XCTAssertNotEqual(record.confidenceLevel, .none)
        XCTAssertEqual(record.title, "가을 아침")
        XCTAssertEqual(record.album, "꽃갈피 둘")
        // 제안의 기준은 실제 곡 값: 비어 있던 항목·바뀔 값
        XCTAssertEqual(record.missingAtIdentification, evaluated.result.missing)
        XCTAssertEqual(record.status(of: .title), .changed, "실제 제목(zzqq)과 다르므로 바뀔 값")
        XCTAssertEqual(record.evidence.reasons.first, "입력한 정보로 다시 식별")
        let saved = try XCTUnwrap(try database.proposals().first)
        XCTAssertEqual(saved.title, "가을 아침")
        XCTAssertEqual(saved.decision, .pending)
    }

    /// 기존 앨범명이 틀린 곡도 입력한 정보로 찾은 앨범의 커버·트랙 번호를 제안한다
    func testIdentifyWithHintsProposesArtworkOfFoundAlbum() async throws {
        let database = try AppDatabase.inMemory()
        let track = LibraryTrack(id: pid(43), title: "Track 01", artist: "Unknown Artist", album: "엉뚱한 앨범", durationMs: 218_500,
                                 hasArtwork: false, fileURL: URL(fileURLWithPath: "/Music/x/01.mp3"),
                                 modifiedDate: Date(timeIntervalSince1970: 1_700_000_000))
        let evaluated = EvaluatedTrack(track: track, result: CompletenessChecker().evaluate(track, fileExists: alwaysExists))
        XCTAssertTrue(evaluated.result.missing.contains(.artwork))
        // 앨범 칸은 지금 값 그대로 둔 채 제목·가수만 입력
        let record = try await makeService(database).identifyWithHints(evaluated, title: "가을 아침", artist: "아이유", album: "엉뚱한 앨범")
        XCTAssertEqual(record.album, "꽃갈피 둘")
        XCTAssertFalse(record.artworkCandidates.isEmpty, "찾은 앨범의 커버 후보")
        XCTAssertNotNil(record.artworkRef)
        XCTAssertEqual(record.trackNo, 1)
        XCTAssertEqual(record.status(of: .artwork), .changed)
    }

    func testOfflineStopsRun() async throws {
        MockURLProtocol.install { _ in (200, Data()) }
        let http = HTTPClient(session: OfflineSession.make(), cache: nil)
        let service = IdentificationService(
            database: try AppDatabase.inMemory(),
            musicBrainz: MusicBrainzProvider(http: http, contact: "t", limiter: RateLimiter(interval: 0)),
            itunes: nil, acoustID: nil)
        do {
            _ = try await service.identify(scope: scope())
            XCTFail("오프라인이면 작업을 멈춰야 함")
        } catch {
            XCTAssertEqual(error as? HTTPError, .offline)
        }
    }
}

/// 항상 '인터넷 연결 없음'을 내는 세션
final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

enum OfflineSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
