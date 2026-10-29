import XCTest
@testable import MTMCore

final class ConfidenceScorerTests: XCTestCase {
    private let scorer = ConfidenceScorer()

    private func evidence(_ build: (inout MatchEvidence) -> Void) -> MatchEvidence {
        var e = MatchEvidence()
        build(&e)
        return e
    }

    func testNoCandidateIsNone() {
        let result = scorer.score(nil)
        XCTAssertEqual(result.level, .none)
        XCTAssertTrue(result.blocksAutoApply)
    }

    func testFingerprintWithTagsIsHigh() {
        let result = scorer.score(evidence {
            $0.fingerprintMatched = true
            $0.titleSimilarity = 1
            $0.artistSimilarity = 1
            $0.durationDeltaMs = 500
        })
        XCTAssertEqual(result.score, 85)
        XCTAssertEqual(result.level, .high)
        XCTAssertFalse(result.blocksAutoApply)
    }

    /// 지문 없이 텍스트만 완벽히 맞아도 HIGH는 아니다 → 검토 대기
    func testTextOnlyPerfectAlbumIsMedium() {
        let result = scorer.score(evidence {
            $0.titleSimilarity = 1
            $0.artistSimilarity = 1
            $0.albumSimilarity = 1
            $0.durationDeltaMs = 0
            $0.trackCountMatches = true
            $0.sourcesAgree = true
        })
        XCTAssertEqual(result.score, 75)
        XCTAssertEqual(result.level, .medium)
        XCTAssertTrue(result.blocksAutoApply)
    }

    /// 같은 앨범의 다른 곡이 지문으로 확인되고 나머지가 모두 맞으면 정확히 HIGH
    func testAlbumFingerprintSiblingReachesHigh() {
        let result = scorer.score(evidence {
            $0.albumFingerprintConfirmed = true
            $0.titleSimilarity = 1
            $0.artistSimilarity = 1
            $0.albumSimilarity = 0.95
            $0.durationDeltaMs = 2_000
        })
        XCTAssertEqual(result.score, 80)
        XCTAssertEqual(result.level, .high)
    }

    func testCloseSimilarityGivesPartialPoints() {
        let result = scorer.score(evidence {
            $0.titleSimilarity = 0.92
            $0.artistSimilarity = 0.86
            $0.durationDeltaMs = 3_000
        })
        XCTAssertEqual(result.score, 12 + 8 + 10)
        XCTAssertEqual(result.level, .low)
    }

    func testAmbiguousAndMismatchPenaltiesClampAtZero() {
        let result = scorer.score(evidence {
            $0.titleSimilarity = 1
            $0.ambiguous = true
            $0.coreMismatch = true
        })
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.level, .low)
    }

    func testDurationOverThreeSecondsGetsNothing() {
        XCTAssertEqual(scorer.score(evidence { $0.durationDeltaMs = 3_001 }).score, 0)
    }

    /// 안전장치: 가수가 완전히 다른 사람으로 바뀌면 점수와 무관하게 자동 적용 안 함
    func testArtistReplacementBlocksAutoApply() {
        var weights = ConfidenceWeights()
        weights.coreMismatch = 0  // 점수가 HIGH여도
        let result = ConfidenceScorer(weights: weights).score(evidence {
            $0.fingerprintMatched = true
            $0.titleSimilarity = 1
            $0.durationDeltaMs = 0
            $0.sourcesAgree = true
            $0.artistReplaced = true
            $0.coreMismatch = true
        })
        XCTAssertEqual(result.level, .high)
        XCTAssertTrue(result.blocksAutoApply)
    }

    func testThresholdBoundaries() {
        var weights = ConfidenceWeights()
        weights.titleExact = 80
        XCTAssertEqual(ConfidenceScorer(weights: weights).score(evidence { $0.titleSimilarity = 1 }).level, .high)
        weights.titleExact = 79
        XCTAssertEqual(ConfidenceScorer(weights: weights).score(evidence { $0.titleSimilarity = 1 }).level, .medium)
        weights.titleExact = 55
        XCTAssertEqual(ConfidenceScorer(weights: weights).score(evidence { $0.titleSimilarity = 1 }).level, .medium)
        weights.titleExact = 54
        XCTAssertEqual(ConfidenceScorer(weights: weights).score(evidence { $0.titleSimilarity = 1 }).level, .low)
    }
}
