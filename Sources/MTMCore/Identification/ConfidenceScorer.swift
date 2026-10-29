import Foundation

public enum ConfidenceLevel: String, Codable, Sendable, CaseIterable {
    case high = "HIGH", medium = "MEDIUM", low = "LOW", none = "NONE"

    public var label: String {
        switch self {
        case .high: return MTMLoc.t("level.high", "높음")
        case .medium: return MTMLoc.t("level.medium", "보통")
        case .low: return MTMLoc.t("level.low", "낮음")
        case .none: return MTMLoc.t("level.none", "식별 실패")
        }
    }
}

/// 신뢰도 가중치. 기본값은 지시서 §6.1 + 앨범 단위 근거 2개(앨범명 일치, 같은 앨범의 지문 확인)
public struct ConfidenceWeights: Codable, Sendable, Equatable {
    public var fingerprint = 40
    public var titleExact = 20
    public var titleClose = 12
    public var artistExact = 15
    public var artistClose = 8
    public var duration = 10
    public var trackCount = 10
    public var sourcesAgree = 10
    public var albumExact = 10
    /// 같은 앨범의 다른 곡이 지문으로 이 릴리스에 확인됨.
    /// 25: 제목·가수·앨범명·길이가 모두 맞으면 정확히 HIGH(80)가 되도록 실데이터(Phase 2)로 맞춘 값
    public var albumFingerprint = 25
    public var ambiguous = -20
    public var coreMismatch = -30
    public var highThreshold = 80
    public var mediumThreshold = 55

    public init() {}
}

/// 점수 근거. 비교할 값이 없으면 nil (예: 비어 있던 제목)
public struct MatchEvidence: Codable, Sendable, Equatable {
    public var fingerprintMatched = false
    public var albumFingerprintConfirmed = false
    public var titleSimilarity: Double?
    public var artistSimilarity: Double?
    public var albumSimilarity: Double?
    public var durationDeltaMs: Int?
    public var trackCountMatches = false
    public var sourcesAgree = false
    /// 후보가 여러 개이고 1·2위 차이가 작음
    public var ambiguous = false
    /// 기존에 입력된 제목·가수명과 핵심적으로 다름
    public var coreMismatch = false
    /// 기존 가수명이 완전히 다른 사람으로 바뀌는 제안 (점수와 무관하게 자동 적용 금지)
    public var artistReplaced = false

    public init() {}
}

public struct ConfidenceResult: Codable, Sendable, Equatable {
    public var score: Int
    public var level: ConfidenceLevel
    public var blocksAutoApply: Bool
    public var reasons: [String]
}

public struct ConfidenceScorer: Sendable {
    public var weights: ConfidenceWeights

    public init(weights: ConfidenceWeights = ConfidenceWeights()) {
        self.weights = weights
    }

    /// - Parameter evidence: nil이면 후보 없음 → NONE
    public func score(_ evidence: MatchEvidence?) -> ConfidenceResult {
        guard let e = evidence else {
            return ConfidenceResult(score: 0, level: .none, blocksAutoApply: true, reasons: ["후보 없음"])
        }
        var total = 0
        var reasons: [String] = []
        func add(_ points: Int, _ reason: String) {
            guard points != 0 else { return }
            total += points
            reasons.append("\(reason) \(points > 0 ? "+" : "")\(points)")
        }

        if e.fingerprintMatched { add(weights.fingerprint, "오디오 지문 일치") }
        else if e.albumFingerprintConfirmed { add(weights.albumFingerprint, "같은 앨범 곡의 지문 확인") }
        if let s = e.titleSimilarity {
            if s >= 0.999 { add(weights.titleExact, "제목 일치") } else if s >= 0.9 { add(weights.titleClose, "제목 유사") }
        }
        if let s = e.artistSimilarity {
            if s >= 0.999 { add(weights.artistExact, "가수 일치") } else if s >= 0.85 { add(weights.artistClose, "가수 유사") }
        }
        if let s = e.albumSimilarity, s >= 0.9 { add(weights.albumExact, "앨범명 일치") }
        if let delta = e.durationDeltaMs, delta <= 3_000 { add(weights.duration, "길이 차이 3초 이내") }
        if e.trackCountMatches { add(weights.trackCount, "앨범 트랙 수 일치") }
        if e.sourcesAgree { add(weights.sourcesAgree, "2개 이상 소스 일치") }
        if e.ambiguous { add(weights.ambiguous, "비슷한 후보가 여럿") }
        if e.coreMismatch { add(weights.coreMismatch, "기존 제목·가수와 불일치") }

        let score = min(100, max(0, total))
        let level: ConfidenceLevel = score >= weights.highThreshold ? .high : score >= weights.mediumThreshold ? .medium : .low
        if e.artistReplaced { reasons.append("가수가 다른 사람으로 바뀜 → 자동 적용 안 함") }
        return ConfidenceResult(score: score, level: level, blocksAutoApply: e.artistReplaced || level != .high, reasons: reasons)
    }
}
