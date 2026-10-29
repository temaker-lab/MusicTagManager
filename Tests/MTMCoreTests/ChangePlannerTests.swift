import XCTest
@testable import MTMCore

final class ChangePlannerTests: XCTestCase {
    private func current(_ build: (inout TrackFields) -> Void = { _ in }) -> TrackFields {
        var fields = TrackFields()
        fields.title = "가을 아침"
        fields.artist = "아이유"
        fields.album = "꽃갈피 둘"
        fields.location = "/Music/아이유/꽃갈피 둘/01 가을 아침.mp3"
        build(&fields)
        return fields
    }

    private let proposed: [String: FieldValue] = [
        "title": .text("가을 아침"), "artist": .text("IU"), "album": .text("꽃갈피 둘"),
        "albumArtist": .text("아이유"), "year": .number(2017), "trackNumber": .number(1), "trackCount": .number(6),
    ]

    private func plan(_ current: TrackFields, policies: WritePolicies = .fillEmptyOnly, artwork: Bool = true) -> (TrackChange, Bool) {
        let result = ChangePlanner.plan(proposed: proposed, hasArtworkCandidates: artwork, current: current, id: pid(1),
                                        rules: CompletenessRules(), policies: policies)
        return (result.change, result.wantsArtwork)
    }

    func testFillEmptyNeverOverwritesExistingValues() {
        let (change, wantsArtwork) = plan(current())
        // 가수명 '아이유'는 있으므로 'IU'로 바꾸지 않는다. 비어 있는 보조 필드만 채운다.
        XCTAssertNil(change.value(of: .artist))
        XCTAssertNil(change.value(of: .title))
        XCTAssertEqual(change.value(of: .albumArtist), .text("아이유"))
        XCTAssertEqual(change.value(of: .year), .number(2017))
        XCTAssertEqual(change.value(of: .trackCount), .number(6))
        XCTAssertTrue(wantsArtwork)
    }

    func testPlaceholdersAreFilled() {
        let (change, _) = plan(current { $0.artist = "Unknown Artist"; $0.album = "알 수 없는 앨범" })
        XCTAssertEqual(change.value(of: .artist), .text("IU"))
        XCTAssertEqual(change.value(of: .album), .text("꽃갈피 둘"))
    }

    func testExistingNumbersAndArtworkKept() {
        let (change, wantsArtwork) = plan(current { $0.year = 2010; $0.trackNumber = 3; $0.artworkCount = 1 })
        XCTAssertNil(change.value(of: .year))
        XCTAssertNil(change.value(of: .trackNumber))
        XCTAssertFalse(wantsArtwork, "기존 커버는 해상도와 관계없이 유지")
    }

    func testReplaceIfDifferentPolicy() {
        var policies = WritePolicies()
        policies.set(.replaceIfDifferent, for: .artist)
        policies.set(.replaceIfDifferent, for: .artwork)
        let (change, wantsArtwork) = plan(current { $0.artworkCount = 1 }, policies: policies)
        XCTAssertEqual(change.value(of: .artist), .text("IU"))
        XCTAssertTrue(wantsArtwork)
        XCTAssertNil(change.value(of: .title), "같은 값은 쓰지 않는다")
    }

    func testDefaultReplacesTitleArtistAlbumOnly() {
        let (change, wantsArtwork) = plan(current { $0.artworkCount = 1; $0.year = 2010 }, policies: WritePolicies())
        XCTAssertEqual(change.value(of: .artist), .text("IU"), "제목·가수·앨범은 다르면 교체가 기본")
        XCTAssertNil(change.value(of: .year), "나머지는 비어 있을 때만")
        XCTAssertFalse(wantsArtwork, "기존 커버는 유지")
        XCTAssertEqual(WritePolicies().policy(for: .album), .replaceIfDifferent)
        XCTAssertEqual(WritePolicies().policy(for: .albumArtist), .fillEmpty)
    }

    func testOverridesStoreOnlyDifferencesFromDefaults() throws {
        var policies = WritePolicies()
        policies.set(.replaceIfDifferent, for: .title)
        XCTAssertEqual(policies.overrides, [:])
        policies.set(.fillEmpty, for: .title)
        XCTAssertEqual(policies.overrides, ["title": .fillEmpty])
        // 예전에 저장된 빈 설정은 새 기본값을 따른다
        let saved = try JSONDecoder().decode(WritePolicies.self, from: Data(#"{"overrides":{}}"#.utf8))
        XCTAssertEqual(saved.policy(for: .artist), .replaceIfDifferent)
    }

    func testNeverPolicy() {
        var policies = WritePolicies()
        policies.set(.never, for: .year)
        policies.set(.never, for: .artwork)
        let (change, wantsArtwork) = plan(current(), policies: policies)
        XCTAssertNil(change.value(of: .year))
        XCTAssertFalse(wantsArtwork)
        XCTAssertEqual(policies.policy(for: .title), .replaceIfDifferent, "바꾸지 않은 필드는 기본값")
    }

    func testNoArtworkCandidatesMeansNoArtwork() {
        XCTAssertFalse(plan(current(), artwork: false).1)
    }

    func testScannedValuesDetectUserEdits() {
        let track = LibraryTrack(id: pid(1), title: "가을 아침", artist: "아이유", album: "꽃갈피 둘", hasArtwork: false)
        let scanned = ScannedValues(track)
        XCTAssertFalse(scanned.differs(from: current()))
        XCTAssertFalse(scanned.differs(from: current { $0.title = "가을 아침".decomposedStringWithCanonicalMapping }))
        XCTAssertTrue(scanned.differs(from: current { $0.artist = "IU" }))
        XCTAssertFalse(scanned.differs(from: current { $0.artworkCount = 1 }), "커버는 비교하지 않는다 (ITLibrary 커버 값을 믿을 수 없음)")
    }

    // Phase 3 실측: 다른 판의 번호 체계가 섞이지 않게

    func testDifferentTrackNumberDropsReleaseNumbering() {
        // 로컬은 사운드트랙 12번, 식별은 싱글 1/11 → 트랙 수·디스크 정보는 쓰지 않는다
        let (change, _) = plan(current { $0.trackNumber = 12 })
        XCTAssertNil(change.value(of: .trackNumber))
        XCTAssertNil(change.value(of: .trackCount))
        XCTAssertNil(change.value(of: .discNumber))
        XCTAssertNil(change.value(of: .discCount))
        XCTAssertEqual(change.value(of: .year), .number(2017))
    }

    func testTrackCountSmallerThanTrackNumberIsDropped() {
        // 트랙 번호 0 → 제안 1을 쓰는 경우는 정상
        XCTAssertEqual(plan(current()).0.value(of: .trackCount), .number(6))
        let change = ChangePlanner.plan(proposed: ["trackCount": .number(8)], hasArtworkCandidates: false,
                                        current: current { $0.trackNumber = 11 }, id: pid(1),
                                        rules: CompletenessRules(), policies: WritePolicies()).change
        XCTAssertNil(change.value(of: .trackCount), "Music이 무시하는 값")
    }

    func testDiscCountSmallerThanDiscNumberIsDropped() {
        let change = ChangePlanner.plan(proposed: ["discCount": .number(1)], hasArtworkCandidates: false,
                                        current: current { $0.discNumber = 2 }, id: pid(1),
                                        rules: CompletenessRules(), policies: WritePolicies()).change
        XCTAssertNil(change.value(of: .discCount))
    }

    // 앱 확인 결과: '알 수 없는 앨범 (날짜)' 변형과 '채울 값 없음' 원인

    func testPlaceholderVariantWithSuffixIsEmpty() {
        let (change, _) = plan(current { $0.album = "알 수 없는 앨범 (2005-07-09 오후 12:48:43)" })
        XCTAssertEqual(change.value(of: .album), .text("꽃갈피 둘"))
        let checker = CompletenessChecker()
        let track = LibraryTrack(id: pid(1), title: "Miniskirt", artist: "Skeewiff",
                                 album: "Unknown Album (2005-07-09)", hasArtwork: true)
        XCTAssertEqual(checker.missingFields(of: track), [.album])
        XCTAssertEqual(checker.missingFields(of: LibraryTrack(id: pid(1), title: "x", artist: "y",
                                                              album: "Unknown Albums Vol. 2", hasArtwork: true)), [])
    }
}
