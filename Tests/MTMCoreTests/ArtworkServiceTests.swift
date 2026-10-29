import XCTest
@testable import MTMCore

final class ArtworkServiceTests: XCTestCase {
    func testLargeImageResizedTo1200Jpeg() throws {
        let result = try ArtworkService.process(makeJPEG(width: 2000, height: 2000), minimumSide: 600)
        XCTAssertEqual(result.width, 1200)
        XCTAssertEqual(result.height, 1200)
        XCTAssertEqual(imageSize(result.data)?.0, 1200)
    }

    func testSmallImageKeepsSize() throws {
        let result = try ArtworkService.process(makeJPEG(width: 800, height: 800), minimumSide: 600)
        XCTAssertEqual(result.width, 800)
    }

    func testRejectsTooSmallNonSquareAndGarbage() {
        XCTAssertThrowsError(try ArtworkService.process(makeJPEG(width: 500, height: 500), minimumSide: 600)) {
            XCTAssertEqual($0 as? ArtworkError, .tooSmall(500, 500))
        }
        XCTAssertThrowsError(try ArtworkService.process(makeJPEG(width: 1000, height: 600), minimumSide: 600)) {
            XCTAssertEqual($0 as? ArtworkError, .notSquare(1000, 600))
        }
        XCTAssertThrowsError(try ArtworkService.process(Data("<html>not found</html>".utf8), minimumSide: 600)) {
            XCTAssertEqual($0 as? ArtworkError, .notImage)
        }
        XCTAssertNoThrow(try ArtworkService.process(makeJPEG(width: 1000, height: 960), minimumSide: 600), "10% 이내는 정사각형")
    }

    func testTriesCandidatesInOrderAndCachesPerCandidate() async throws {
        let good = makeJPEG(width: 1400, height: 1400)
        MockURLProtocol.install { request in
            switch request.url?.host {
            case "bad.example": return (404, Data())
            case "small.example": return (200, makeJPEG(width: 300, height: 300))
            default: return (200, good)
            }
        }
        let service = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]),
                                     http: HTTPClient(session: MockURLProtocol.session(), cache: nil, baseBackoff: 0.01),
                                     limiter: RateLimiter(interval: 0))
        let candidates = ["itunes:https://bad.example/a.jpg", "caa:https://small.example/b.jpg", "caa:https://good.example/c.jpg"]
        let first = await service.prepare(candidates)
        let prepared = try XCTUnwrap(first)
        XCTAssertEqual(prepared.source, "caa:https://good.example/c.jpg")
        XCTAssertEqual(prepared.width, 1200)
        XCTAssertEqual(imageSize(try Data(contentsOf: prepared.file))?.0, 1200)

        let requests = MockURLProtocol.requests.count
        let again = await service.prepare(candidates)
        XCTAssertEqual(again, prepared)
        XCTAssertEqual(MockURLProtocol.requests.count, requests, "같은 앨범의 다음 곡은 다시 내려받지 않는다")
    }

    func testSiblingArtworkAcceptedEvenIfSmall() async throws {
        let music = FakeMusic([pid(9): TrackFields()])
        music.setArtworkData(pid(9), [makeJPEG(width: 300, height: 300)])
        let service = ArtworkService(directory: temporaryDirectory(), music: music)
        let result = await service.prepare(["track:\(pid(9).hex)"])
        let prepared = try XCTUnwrap(result)
        XCTAssertEqual(prepared.width, 300)
    }

    func testNoUsableCandidate() async {
        let service = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]))
        let prepared = await service.prepare(["track:\(pid(9).hex)", "nonsense"])
        XCTAssertNil(prepared)
    }

    /// 앱 확인 결과: Cover Art Archive 커버는 400~500px가 많아 600px 기준에 모두 걸렸다
    func testLowResolutionFallbackWhenNoLargeCover() async throws {
        MockURLProtocol.install { request in
            request.url?.path.contains("release-group") == true ? (404, Data()) : (200, makeJPEG(width: 400, height: 396))
        }
        let http = HTTPClient(session: MockURLProtocol.session(), cache: nil, baseBackoff: 0.01)
        let candidates = ["caa:https://coverartarchive.org/release/a/front-1200", "caa:https://coverartarchive.org/release-group/b/front-1200"]

        let strict = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]), http: http,
                                    limiter: RateLimiter(interval: 0), lowResolutionMinimum: nil)
        let none = await strict.prepareWithReport(candidates)
        XCTAssertNil(none.prepared)
        XCTAssertEqual(none.failures, ["Cover Art Archive: 해상도가 낮습니다 (400×396)", "Cover Art Archive(대표): 커버 없음"])

        let lenient = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]), http: http, limiter: RateLimiter(interval: 0))
        let result = await lenient.prepareWithReport(candidates)
        XCTAssertEqual(result.prepared?.width, 400)
        let requests = MockURLProtocol.requests.count
        _ = await lenient.prepareWithReport(candidates)
        XCTAssertEqual(MockURLProtocol.requests.count, requests, "두 번째 기준으로 다시 볼 때도 다시 내려받지 않는다")
    }

    func testUserFileAllowsAnySizeAndShape() async throws {
        let file = temporaryDirectory().appendingPathComponent("cover.jpg")
        try makeJPEG(width: 500, height: 300).write(to: file)
        let service = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]))
        let prepared = await service.prepare(["file:\(file.path)"])
        XCTAssertEqual(prepared?.width, 500)
    }

    /// 앱 확인 결과: 이미지가 없는 Cover Art Archive 후보가 ‘적용 시 변경’에 커버로 표시되고 적용하면 실패
    func testChecksAreRecordedAndUnusableCandidatesExcludedFromPreview() async throws {
        MockURLProtocol.install { request in
            request.url?.host == "missing.example" ? (404, Data()) : (200, makeJPEG(width: 450, height: 450))
        }
        let database = try AppDatabase.inMemory()
        let http = HTTPClient(session: MockURLProtocol.session(), cache: nil, baseBackoff: 0.01)
        let service = ArtworkService(directory: temporaryDirectory(), music: FakeMusic([:]), http: http,
                                     limiter: RateLimiter(interval: 0), checkStore: database)
        let missing = "caa:https://missing.example/release-group/x/front-1200"
        let small = "caa:https://small.example/release/y/front-1200"
        _ = await service.prepareWithReport([missing, small])
        let checks = try database.artworkChecks()
        XCTAssertEqual(checks[missing]?.usable, false)
        XCTAssertEqual(checks[missing]?.reason, "커버 없음")
        XCTAssertEqual(checks[small]?.usable, true)
        XCTAssertEqual(checks[small]?.width, 450)

        var proposal = ProposalRecord(persistentID: pid(1).hex, albumGroupKey: "g", artworkCandidates: [missing],
                                      fieldStatus: [:], evidence: ProposalEvidence(match: nil, reasons: [], error: nil),
                                      confidenceScore: 90, confidenceLevel: .high, blocksAutoApply: false,
                                      decision: .pending, identifiedAt: Date())
        var track = completeTrack(1)
        track.hasArtwork = false
        let preview = proposal.preview(current: track, rules: CompletenessRules(), policies: WritePolicies(), artworkChecks: checks)
        XCTAssertEqual(preview.fields, [], "쓸 수 없는 커버는 적용 시 변경에서 뺀다")
        XCTAssertEqual(preview.reason, "커버 없음 — Cover Art Archive(대표): 커버 없음")

        proposal.artworkCandidates = [missing, small]
        XCTAssertEqual(proposal.usableArtworkCandidates(checks: checks, allowLowResolution: true), [small])
        XCTAssertEqual(proposal.usableArtworkCandidates(checks: checks, allowLowResolution: false), [], "저해상도 허용을 끄면 450px도 제외")
        XCTAssertEqual(proposal.preview(current: track, rules: CompletenessRules(), policies: WritePolicies(),
                                        artworkChecks: checks).fields, [.artwork])
        // 아직 확인하지 않은 후보는 남겨 둔다
        proposal.artworkCandidates = ["itunes:https://unchecked.example/a.jpg"]
        XCTAssertEqual(proposal.usableArtworkCandidates(checks: checks, allowLowResolution: true).count, 1)
    }
}
