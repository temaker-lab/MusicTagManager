import XCTest
@testable import MTMCore

final class PersistentIDTests: XCTestCase {
    func testHexIsSixteenUppercaseDigits() {
        XCTAssertEqual(PersistentID(0xBE2EBB05EA3BF7CE).hex, "BE2EBB05EA3BF7CE")
        XCTAssertEqual(PersistentID(5).hex, "0000000000000005")
    }

    func testFromITLibraryNumber() {
        let unsigned = NSNumber(value: UInt64(0xBE2EBB05EA3BF7CE))
        XCTAssertEqual(PersistentID(number: unsigned).hex, "BE2EBB05EA3BF7CE")
        // 부호 있는 64비트로 담겨 와도 같은 ID
        let signed = NSNumber(value: Int64(bitPattern: 0xBE2EBB05EA3BF7CE))
        XCTAssertEqual(PersistentID(number: signed), PersistentID(number: unsigned))
    }

    func testHexRoundTrip() {
        for value: UInt64 in [0, 1, 0x0BE217367CEFB52C, .max] {
            XCTAssertEqual(PersistentID(hex: PersistentID(value).hex)?.rawValue, value)
        }
        XCTAssertEqual(PersistentID(hex: "be2ebb05ea3bf7ce")?.hex, "BE2EBB05EA3BF7CE")
    }

    func testRejectsMalformedHex() {
        // Phase 0: AppleScript는 16자를 넘는 문자열도 다른 곡에 매칭시켰다 → 반드시 거부
        let invalid = ["", "BE2E", "BE2EBB05EA3BF7CE0", "BE2EBB05EA3BF7CE A77E1884D118D445",
                       " BE2EBB05EA3BF7C", "GE2EBB05EA3BF7CE", "+E2EBB05EA3BF7CE", "BE2EBB05EA3BF7C\n"]
        for string in invalid {
            XCTAssertNil(PersistentID(hex: string), string)
        }
    }

    func testCodableUsesHexString() throws {
        let data = try JSONEncoder().encode([PersistentID(0xA)])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["000000000000000A"]"#)
        XCTAssertEqual(try JSONDecoder().decode([PersistentID].self, from: data), [PersistentID(0xA)])
        XCTAssertThrowsError(try JSONDecoder().decode([PersistentID].self, from: Data(#"["xyz"]"#.utf8)))
    }
}
