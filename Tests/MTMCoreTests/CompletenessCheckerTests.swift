import XCTest
@testable import MTMCore

final class CompletenessCheckerTests: XCTestCase {
    private let checker = CompletenessChecker()

    private func evaluate(_ track: LibraryTrack, exists: Bool = true, rules: CompletenessRules = .init()) -> CompletenessResult {
        CompletenessChecker(rules: rules).evaluate(track) { _ in exists }
    }

    // MARK: 필수 케이스 (지시서 §10)

    func testAllFourPresentIsComplete() {
        XCTAssertEqual(evaluate(completeTrack(1)), CompletenessResult(.complete))
    }

    func testOnlyArtworkMissing() {
        var track = completeTrack(1)
        track.hasArtwork = false
        XCTAssertEqual(evaluate(track), CompletenessResult(.incomplete, missing: [.artwork]))
    }

    func testOnlyAlbumMissing() {
        var track = completeTrack(1)
        track.album = nil
        XCTAssertEqual(evaluate(track), CompletenessResult(.incomplete, missing: [.album]))
    }

    func testWhitespaceOnlyValuesAreEmpty() {
        var track = completeTrack(1)
        track.artist = "   "
        track.album = "\u{3000}\n"
        XCTAssertEqual(evaluate(track).missing, [.artist, .album])
    }

    func testPlaceholderValuesAreEmpty() {
        var track = completeTrack(1)
        track.artist = "unknown ARTIST"
        track.album = "알 수 없는 앨범"
        XCTAssertEqual(evaluate(track).missing, [.artist, .album])

        track.artist = "Various"
        track.album = "Album"
        XCTAssertEqual(evaluate(track).missing, [.artist])
    }

    func testPlaceholdersCanBeDisabled() {
        var rules = CompletenessRules()
        rules.treatPlaceholdersAsEmpty = false
        var track = completeTrack(1)
        track.artist = "Unknown Artist"
        track.title = "Track 01"
        XCTAssertEqual(evaluate(track, rules: rules), CompletenessResult(.complete))
    }

    func testNFDHangulValues() {
        var track = completeTrack(1)
        track.artist = "아이유".decomposedStringWithCanonicalMapping
        track.album = "꽃갈피".decomposedStringWithCanonicalMapping
        XCTAssertEqual(evaluate(track), CompletenessResult(.complete))

        track.artist = "알 수 없는 아티스트".decomposedStringWithCanonicalMapping
        XCTAssertEqual(evaluate(track).missing, [.artist])
    }

    func testTitlePlaceholderPatterns() {
        // 접두어형(Track N)·빈 제목은 가수·앨범이 채워져 있어도 플레이스홀더로 본다
        for title in ["Track 01", "트랙 01", "track1", ""] {
            var track = completeTrack(1)
            track.title = title
            XCTAssertEqual(evaluate(track).missing, [.title], title)
        }
        // 숫자만으로 된 제목(예: Britney Spears "3")은 실제 곡 제목일 수 있다 → 가수·앨범이 있으면 정상으로 본다
        var numeric = completeTrack(1)
        numeric.title = "07"
        XCTAssertEqual(evaluate(numeric).missing, [], "숫자 제목 + 가수·앨범 있음 → 정상")
        // 가수·앨범도 비어 있으면 숫자 제목은 플레이스홀더로 본다
        numeric.artist = nil
        numeric.album = nil
        XCTAssertEqual(Set(evaluate(numeric).missing), Set([.title, .artist, .album]))
    }

    // MARK: 제목 = 파일명 (Phase 0 결과로 규칙 변경)

    func testTitleEqualToFilenameIsNotEmptyWhenTagsPresent() {
        // Music이 파일명을 제목으로 바꿔 두므로 정상 곡도 제목 == 파일명이다
        let track = completeTrack(1, title: "Bring It Home To Me", fileName: "Bring It Home To Me")
        XCTAssertEqual(evaluate(track), CompletenessResult(.complete))
    }

    func testFilenameLikeTitleWithMissingArtistIsEmpty() {
        var track = completeTrack(1, title: "Toto - Africa", fileName: "Toto - Africa")
        track.artist = nil
        XCTAssertEqual(evaluate(track).missing, [.title, .artist])

        track = completeTrack(2, title: "05 Make It Happen", fileName: "05 Make It Happen")
        track.album = "Unknown Album"
        XCTAssertEqual(evaluate(track).missing, [.title, .album])

        track = completeTrack(3, title: "03.Forever", fileName: "03.Forever")
        track.artist = ""
        XCTAssertEqual(evaluate(track).missing, [.title, .artist])
    }

    func testFilenameLikeTitleKeptWhenOtherTagsPresent() {
        // 다른 정보가 다 있으면 기존 제목을 건드리지 않는다 (덮어쓰기 금지 원칙)
        let track = completeTrack(1, title: "21 Questions", fileName: "21 Questions")
        XCTAssertEqual(evaluate(track), CompletenessResult(.complete))
    }

    func testFilenameLikeTitleRuleCanBeDisabled() {
        var rules = CompletenessRules()
        rules.treatFilenameLikeTitleAsEmpty = false
        var track = completeTrack(1, title: "Toto - Africa", fileName: "Toto - Africa")
        track.artist = nil
        XCTAssertEqual(evaluate(track, rules: rules).missing, [.artist])
    }

    func testFilenameComparisonUsesNFC() {
        var track = completeTrack(1, title: "임재범 - 너를위해",
                                  fileName: "임재범 - 너를위해".decomposedStringWithCanonicalMapping)
        track.artist = nil
        XCTAssertEqual(evaluate(track).missing, [.title, .artist])
    }

    // MARK: 필터 A

    func testCloudOnlyTrackIsExcluded() {
        var track = completeTrack(1)
        track.fileURL = nil
        track.isCloud = true
        XCTAssertEqual(evaluate(track), CompletenessResult(.excludedCloud))
    }

    func testMissingFileIsExcluded() {
        XCTAssertEqual(evaluate(completeTrack(1), exists: false), CompletenessResult(.excludedMissingFile))
        var track = completeTrack(1)
        track.fileURL = nil
        XCTAssertEqual(evaluate(track), CompletenessResult(.excludedMissingFile))
    }

    func testNonSongIsExcludedEvenIfIncomplete() {
        var track = completeTrack(1)
        track.isSong = false
        track.hasArtwork = false
        XCTAssertEqual(evaluate(track), CompletenessResult(.excludedUnsupported))
    }

    func testRulesVersionChangesWithRules() {
        var rules = CompletenessRules()
        let original = rules.version
        XCTAssertEqual(original, CompletenessRules().version)
        rules.albumPlaceholders.append("No Album")
        XCTAssertNotEqual(rules.version, original)
    }
}
