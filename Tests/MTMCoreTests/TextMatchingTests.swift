import XCTest
@testable import MTMCore

final class TextMatchingTests: XCTestCase {
    func testMatchKeyStripsFeaturingAndBrackets() {
        XCTAssertEqual(Normalizer.matchKey("사랑에 아파한 날들 (Feat. 윤하)"), "사랑에아파한날들")
        XCTAssertEqual(Normalizer.matchKey("People Pt.2 feat. IU"), "peoplept2")
        XCTAssertEqual(Normalizer.matchKey("Hello [Remastered 2011]"), "hello")
        XCTAssertEqual(Normalizer.matchKey("Song - Prod. by Someone"), Normalizer.matchKey("Song -"))
        XCTAssertEqual(Normalizer.matchKey("(Intro)"), "intro")  // 전체가 괄호면 안의 내용
        XCTAssertEqual(Normalizer.matchKey("가을 아침".decomposedStringWithCanonicalMapping), "가을아침")
    }

    func testVersionTags() {
        XCTAssertEqual(Normalizer.versionTags("살아야지 [Piano Ver]"), [])
        XCTAssertEqual(Normalizer.versionTags("사랑에 아파한 날들 (Inst.)"), [.instrumental])
        XCTAssertEqual(Normalizer.versionTags("Truth (Live Version)"), [.live])
        XCTAssertEqual(Normalizer.versionTags("Ba Bump (Erick Sermon remix)"), [.remix])
        XCTAssertEqual(Normalizer.versionTags("Make It Happen (Unplugged)"), [.acoustic])
        XCTAssertEqual(Normalizer.versionTags("Last Christmas (a cappella)"), [.acappella])
        XCTAssertEqual(Normalizer.versionTags("Acapella Version"), [.acappella])
    }

    func testArtistVariantsAndSimilarity() {
        XCTAssertEqual(Normalizer.artistNameVariants("아이유(IU)"), ["아이유(IU)", "아이유", "IU"])
        XCTAssertEqual(Normalizer.artistNameVariants("Agust D feat. IU"), ["Agust D feat. IU", "Agust D"])
        XCTAssertEqual(Normalizer.artistNameVariants("HIGH4;IU"), ["HIGH4;IU", "HIGH4"])
        XCTAssertEqual(Normalizer.artistSimilarity("아이유(IU)", "IU"), 1)
        XCTAssertEqual(Normalizer.artistSimilarity("T-Square", "T‐SQUARE"), 1)  // 유니코드 하이픈
        XCTAssertLessThan(Normalizer.artistSimilarity("아이유", "IU"), 0.5)
    }

    func testSimilarity() {
        XCTAssertEqual(Normalizer.similarity("Hello", "hello!"), 1)
        XCTAssertEqual(Normalizer.similarity("", "x"), 0)
        XCTAssertGreaterThanOrEqual(Normalizer.similarity("There Times A Lady", "Three Times A Lady"), 0.85)
        XCTAssertLessThan(Normalizer.similarity("Africa", "Rosanna"), 0.5)
        XCTAssertTrue(Normalizer.containsHangul("꽃갈피 둘"))
        XCTAssertFalse(Normalizer.containsHangul("A Flower Bookmark"))
    }

    func testTitleHints() {
        XCTAssertEqual(TitleHints.parse("Toto - Africa"), TitleHints(artist: "Toto", title: "Africa"))
        XCTAssertEqual(TitleHints.parse("05 Make It Happen"), TitleHints(title: "Make It Happen", trackNumber: 5))
        XCTAssertEqual(TitleHints.parse("03.Forever"), TitleHints(title: "Forever", trackNumber: 3))
        XCTAssertEqual(TitleHints.parse("1-04 Someone"), TitleHints(title: "Someone", trackNumber: 4, discNumber: 1))
        XCTAssertEqual(TitleHints.parse("Abu&Noreen - 09 - Tao delicado"),
                       TitleHints(artist: "Abu&Noreen", title: "Tao delicado", trackNumber: 9))
        XCTAssertEqual(TitleHints.parse("T-Square - EXCITING PEACE - 02 - Dandelion Hill"),
                       TitleHints(artist: "T-Square", album: "EXCITING PEACE", title: "Dandelion Hill", trackNumber: 2))
        XCTAssertEqual(TitleHints.parse("01 너를 위해"), TitleHints(title: "너를 위해", trackNumber: 1))
        XCTAssertNil(TitleHints.parse("Bring It Home To Me"))
        XCTAssertNil(TitleHints.parse(""))
    }
}
