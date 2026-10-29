import XCTest
@testable import MTMCore

final class NormalizerTests: XCTestCase {
    func testCleanConvertsNFDToNFCAndTrims() {
        let nfd = "아이유".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(nfd.unicodeScalars.count, "아이유".unicodeScalars.count)
        XCTAssertEqual(Normalizer.clean("  \(nfd)\u{3000}\n"), "아이유")
        XCTAssertEqual(Normalizer.clean(nil), "")
    }

    func testCompareKeyIgnoresCaseAndCollapsesSpaces() {
        XCTAssertEqual(Normalizer.compareKey("  Unknown   ARTIST "), "unknown artist")
        XCTAssertEqual(Normalizer.compareKey("알 수 없는 앨범".decomposedStringWithCanonicalMapping), "알 수 없는 앨범")
    }

    func testSearchVariantsForSymbolSpacing() {
        XCTAssertEqual(Normalizer.searchVariants("2 + 1"), ["2 + 1", "2+1", "2 1"])
        XCTAssertEqual(Normalizer.searchVariants("2+1"), ["2+1", "2 1"])
        XCTAssertEqual(Normalizer.searchVariants("안부"), ["안부"])
        XCTAssertEqual(Normalizer.searchVariants("  "), [])
        // 매칭 키는 기호·공백을 무시하므로 띄어쓰기가 달라도 같은 곡
        XCTAssertEqual(Normalizer.similarity("2 + 1", "2+1"), 1)
    }
}
