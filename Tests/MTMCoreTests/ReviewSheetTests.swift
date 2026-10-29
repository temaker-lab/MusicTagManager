import XCTest
@testable import MTMCore

final class ReviewSheetTests: XCTestCase {
    func testCSVRoundTripWithQuotesCommasNewlines() {
        let rows = [["a", "b,c", "say \"hi\""], ["줄\n바꿈", "", "끝"]]
        XCTAssertEqual(CSV.decode(CSV.encode(rows)), rows)
        XCTAssertEqual(CSV.decode("\u{FEFF}x,y\r\n1,2\r\n"), [["x", "y"], ["1", "2"]])
        XCTAssertEqual(CSV.decode("x,y\n\n1,2"), [["x", "y"], ["1", "2"]], "빈 줄은 건너뜀")
    }

    private func proposal(_ id: UInt64) -> ProposalRecord {
        ProposalRecord(persistentID: pid(id).hex, albumGroupKey: "g", title: "Kiss the Rain", artist: "Yiruma",
                       album: "First Love", year: 2001, trackNo: 3, fieldStatus: [:],
                       evidence: ProposalEvidence(match: nil, reasons: ["제목 일치 +20"], error: nil),
                       confidenceScore: 55, confidenceLevel: .medium, blocksAutoApply: true, decision: .pending,
                       identifiedAt: Date())
    }

    func testExportThenImportEditsAndDecisions() throws {
        let proposals = [proposal(1), proposal(2), proposal(3)]
        let csv = ReviewSheet.export(proposals: proposals, tracks: [pid(1): completeTrack(1)], statuses: [pid(1).hex: "검토 대기"])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}persistent_id,"))

        // 엑셀에서 고친 것처럼: 1번 승인, 2번 제목 수정, 3번 거절
        var rows = CSV.decode(csv)
        rows[1][1] = "승인"
        rows[2][8] = "Kiss The Rain (Piano)"
        rows[3][1] = "거절"
        let result = ReviewSheet.parse(CSV.encode(rows), proposals: Dictionary(uniqueKeysWithValues: proposals.map { ($0.persistentID, $0) }))
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.approve, [pid(1)])
        XCTAssertEqual(result.reject, [pid(3)])
        XCTAssertEqual(Array(result.overrides.keys), [pid(2)])
        XCTAssertEqual(result.overrides[pid(2)]?[.title], .text("Kiss The Rain (Piano)"))
        XCTAssertEqual(result.overrides[pid(2)]?[.year], .number(2001))
    }

    func testImportRejectsForeignFilesAndBadValues() {
        XCTAssertFalse(ReviewSheet.parse("a,b\n1,2", proposals: [:]).errors.isEmpty)
        var row = Array(repeating: "", count: ReviewSheet.header.count)
        row[0] = pid(1).hex
        row[13] = "이천일"
        let unknown = CSV.encode([ReviewSheet.header, row, ["FFFFFFFFFFFFFFFF"]])
        let result = ReviewSheet.parse(unknown, proposals: [pid(1).hex: proposal(1)])
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertTrue(result.errors[0].contains("숫자"))
        XCTAssertTrue(result.errors[1].contains("알 수 없는 곡"))
    }
}
