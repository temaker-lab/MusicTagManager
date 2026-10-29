import XCTest
@testable import MTMCore

final class MatchingRulesTests: XCTestCase {
    private func release(_ id: String, _ title: String, type: String? = "Album", secondary: [String] = [],
                         date: String? = "2000-01-01", artist: String = "Artist") -> ReleaseCandidate {
        ReleaseCandidate(source: .musicbrainz, id: id, title: title, artist: artist, date: date,
                         primaryType: type, secondaryTypes: secondary)
    }

    // MARK: 릴리스 선택 규칙 (Phase 0)

    func testCompilationLiveRemixAndVariousArtistsComeLast() {
        let ordered = ReleasePreference.sorted([
            release("comp", "Smash Hits", secondary: ["Compilation"], date: "1990"),
            release("live", "Live", secondary: ["Live"], date: "1991"),
            release("va", "Hits", date: "1992", artist: "Various Artists"),
            release("orig", "Original", date: "2010"),
        ], preferHangul: false)
        XCTAssertEqual(ordered.first?.id, "orig")
    }

    func testAlbumBeforeEarlierPreReleaseSingle() {
        let ordered = ReleasePreference.sorted([
            release("single", "가을 아침", type: "Single", date: "2017-09-18"),
            release("ep", "꽃갈피 둘", type: "EP", date: "2017-09-22"),
        ], preferHangul: true)
        XCTAssertEqual(ordered.map(\.id), ["ep", "single"])
    }

    func testHangulTitlePreferredForKoreanSongs() {
        let ordered = ReleasePreference.sorted([
            release("en", "A Flower Bookmark, Pt. 2", type: "EP"),
            release("ko", "꽃갈피 둘", type: "EP"),
        ], preferHangul: true)
        XCTAssertEqual(ordered.first?.id, "ko")
    }

    func testEarliestDateBreaksTies() {
        let ordered = ReleasePreference.sorted([release("b", "B", date: "2001"), release("a", "A", date: "1999")], preferHangul: false)
        XCTAssertEqual(ordered.first?.id, "a")
    }

    // MARK: 트랙 매칭

    private let tracklist = [
        ReleaseTrack(discNumber: 1, trackNumber: 1, title: "가을 아침", artist: "IU", durationMs: 218_000, recordingID: "r1"),
        ReleaseTrack(discNumber: 1, trackNumber: 2, title: "비밀의 화원", artist: "IU", durationMs: 224_000, recordingID: "r2"),
        ReleaseTrack(discNumber: 1, trackNumber: 3, title: "사랑에 아파한 날들 (Inst.)", artist: "IU", durationMs: 269_000, recordingID: "r3"),
    ]

    func testMatchesByTitleDurationAndPosition() {
        let matches = TrackMatcher.match([
            LocalTrackInfo(id: pid(1), title: "비밀의 화원", durationMs: 224_500, trackNumber: 2),
            LocalTrackInfo(id: pid(2), title: "가을아침", durationMs: 217_000),
        ], to: tracklist)
        XCTAssertEqual(matches[pid(1)]?.releaseTrack.trackNumber, 2)
        XCTAssertEqual(matches[pid(1)]?.positionMatches, true)
        XCTAssertEqual(matches[pid(2)]?.releaseTrack.trackNumber, 1)
        XCTAssertEqual(matches[pid(2)]?.durationDeltaMs, 1_000)
    }

    func testInstrumentalNotMatchedToOriginal() {
        let matches = TrackMatcher.match([LocalTrackInfo(id: pid(1), title: "사랑에 아파한 날들", durationMs: 269_000)], to: tracklist)
        XCTAssertNil(matches[pid(1)])
    }

    func testUnknownTitleNeedsDurationAndPosition() {
        let matches = TrackMatcher.match([
            LocalTrackInfo(id: pid(1), title: nil, durationMs: 224_100, trackNumber: 2),
            LocalTrackInfo(id: pid(2), title: nil, durationMs: 224_100, trackNumber: nil),
        ], to: tracklist)
        XCTAssertEqual(matches[pid(1)]?.releaseTrack.trackNumber, 2)
        XCTAssertNil(matches[pid(2)])
    }

    func testFingerprintRecordingWinsAndIsOneToOne() {
        let matches = TrackMatcher.match([
            LocalTrackInfo(id: pid(1), title: "가을 아침", durationMs: 218_000),
            LocalTrackInfo(id: pid(2), title: "Unknown", durationMs: 0, recordingIDs: ["r1"]),
        ], to: tracklist)
        XCTAssertEqual(matches[pid(2)]?.releaseTrack.recordingID, "r1")
        XCTAssertEqual(matches[pid(2)]?.byFingerprint, true)
        XCTAssertNil(matches[pid(1)], "같은 트랙에 두 곡을 배정하지 않는다")
    }

    func testSameTracklistComparesDurations() {
        let itunes = tracklist.map { var t = $0; t.title = "English"; t.durationMs = ($0.durationMs ?? 0) + 800; return t }
        XCTAssertTrue(AlbumResolver.sameTracklist(tracklist, itunes))
        let other = tracklist.map { var t = $0; t.durationMs = ($0.durationMs ?? 0) + 20_000; return t }
        XCTAssertFalse(AlbumResolver.sameTracklist(tracklist, other))
    }

    // MARK: 그룹핑

    func testGroupsByAlbumAndSinglesForMissingAlbum() {
        var a1 = completeTrack(1); a1.hasArtwork = false
        var a2 = completeTrack(2); a2.artist = nil  // 가수명이 비어도 같은 앨범으로 합친다
        let a3 = completeTrack(3)                   // 완비 곡 → 참고
        var single = completeTrack(4); single.album = "Unknown Album"
        let checker = CompletenessChecker()
        let scope = [a1, a2, a3, single].map { EvaluatedTrack(track: $0, result: checker.evaluate($0, fileExists: alwaysExists)) }
        let groups = IdentificationService.makeGroups(scope: scope)
        XCTAssertEqual(groups.count, 2)
        let album = groups.first { !$0.isSingle }!
        XCTAssertEqual(Set(album.targets.map(\.id)), [pid(1), pid(2)])
        XCTAssertEqual(album.references.map(\.id), [pid(3)])
        XCTAssertTrue(groups.contains { $0.isSingle && $0.targets.map(\.id) == [pid(4)] })
    }
}
