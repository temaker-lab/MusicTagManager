import Foundation

/// 작업 대상 여부를 가르는 필수 4개 항목
public enum RequiredField: String, CaseIterable, Codable, Sendable, Comparable {
    case artwork, title, artist, album

    public var label: String {
        switch self {
        case .artwork: return MTMLoc.t("field.artwork", "앨범커버")
        case .title: return MTMLoc.t("field.title", "곡 제목")
        case .artist: return MTMLoc.t("field.artist", "가수명")
        case .album: return MTMLoc.t("field.album", "앨범명")
        }
    }

    public static func < (lhs: RequiredField, rhs: RequiredField) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum Completeness: String, Codable, Sendable, CaseIterable {
    case complete = "COMPLETE"
    case incomplete = "INCOMPLETE"
    case excludedCloud = "EXCLUDED_CLOUD"
    case excludedMissingFile = "EXCLUDED_MISSING_FILE"
    /// 뮤직비디오·팟캐스트 등 음악 곡이 아닌 항목
    case excludedUnsupported = "EXCLUDED_UNSUPPORTED"

    /// 식별·적용 파이프라인 대상인가
    public var isEligible: Bool { self == .incomplete }

    public var isExcluded: Bool {
        switch self {
        case .excludedCloud, .excludedMissingFile, .excludedUnsupported: return true
        case .complete, .incomplete: return false
        }
    }

    public var label: String {
        switch self {
        case .complete: return MTMLoc.t("completeness.complete", "완비")
        case .incomplete: return MTMLoc.t("completeness.incomplete", "정리 대상")
        case .excludedCloud: return MTMLoc.t("completeness.excludedCloud", "클라우드 전용")
        case .excludedMissingFile: return MTMLoc.t("completeness.excludedMissingFile", "파일 없음")
        case .excludedUnsupported: return MTMLoc.t("completeness.excludedUnsupported", "음악 아님")
        }
    }
}

/// "입력되어 있음" 판정 규칙 (설정에서 편집)
public struct CompletenessRules: Codable, Sendable, Equatable {
    /// 플레이스홀더 값을 빈 값으로 간주
    public var treatPlaceholdersAsEmpty = true
    public var artistPlaceholders = ["Unknown Artist", "알 수 없는 아티스트", "Various", "Various Artists", "여러 음악가"]
    public var albumPlaceholders = ["Unknown Album", "알 수 없는 앨범"]
    /// 곡 제목 플레이스홀더 (정규식, 대소문자 무시)
    public var titlePlaceholderPatterns = [#"^(track|트랙)\s*\d+$"#, #"^\d+$"#]
    /// 제목이 파일명 그대로이고 `아티스트 - 제목`·`05 제목` 형태이며, 가수명이나 앨범명도 비어 있으면 제목도 빈 값으로 본다.
    /// 단순 '제목 == 파일명' 비교는 쓰지 않는다: Music이 파일명을 제목으로 바꿔 두므로 정상 곡 대부분이 걸린다(Phase 0).
    public var treatFilenameLikeTitleAsEmpty = true

    public init() {}

    /// 규칙이 바뀌면 값이 달라져 다음 스캔에서 전체 재검사가 일어난다.
    public var version: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data()
        var hash: UInt64 = 0xcbf29ce484222325  // FNV-1a
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public struct CompletenessResult: Hashable, Sendable {
    public let completeness: Completeness
    /// 비어 있는 필수 항목 (정리 대상일 때만)
    public let missing: [RequiredField]

    public init(_ completeness: Completeness, missing: [RequiredField] = []) {
        self.completeness = completeness
        self.missing = missing
    }
}

public struct CompletenessChecker: @unchecked Sendable {  // NSRegularExpression은 불변·스레드 안전
    public let rules: CompletenessRules
    private let artistPlaceholders: Set<String>
    private let albumPlaceholders: Set<String>
    private let titlePatterns: [NSRegularExpression]

    /// `05 제목`, `03.제목`, `1-04 제목`, `아티스트 - 제목`
    private static let filenameLikeTitle = try! NSRegularExpression(
        pattern: #"^\d{1,3}(?:-\d{1,3})?[\s._-]+\S|\S\s+-\s+\S"#)

    public init(rules: CompletenessRules = CompletenessRules()) {
        self.rules = rules
        artistPlaceholders = Set(rules.artistPlaceholders.map(Normalizer.compareKey))
        albumPlaceholders = Set(rules.albumPlaceholders.map(Normalizer.compareKey))
        titlePatterns = rules.titlePlaceholderPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }

    /// 필터 A(로컬 파일·클라우드) → 필터 B(필수 4개 항목) 순서로 판정한다.
    public func evaluate(_ track: LibraryTrack, fileExists: (URL) -> Bool) -> CompletenessResult {
        guard track.isSong else { return CompletenessResult(.excludedUnsupported) }
        guard let url = track.fileURL else {
            return CompletenessResult(track.isCloud ? .excludedCloud : .excludedMissingFile)
        }
        guard fileExists(url) else { return CompletenessResult(.excludedMissingFile) }
        let missing = missingFields(of: track)
        return CompletenessResult(missing.isEmpty ? .complete : .incomplete, missing: missing)
    }

    /// 앨범커버는 메타데이터 플래그로만 판정한다 (목록화 단계에서 이미지 디코딩 안 함)
    public func missingFields(of track: LibraryTrack) -> [RequiredField] {
        let artistEmpty = isEmpty(track.artist, placeholders: artistPlaceholders)
        let albumEmpty = isEmpty(track.album, placeholders: albumPlaceholders)
        var missing: [RequiredField] = []
        if !track.hasArtwork { missing.append(.artwork) }
        if isTitleEmpty(track, otherTextMissing: artistEmpty || albumEmpty) { missing.append(.title) }
        if artistEmpty { missing.append(.artist) }
        if albumEmpty { missing.append(.album) }
        return missing
    }

    private func isEmpty(_ value: String?, placeholders: Set<String>) -> Bool {
        let key = Normalizer.compareKey(value)
        if key.isEmpty { return true }
        guard rules.treatPlaceholdersAsEmpty else { return false }
        // Music이 붙이는 변형도 플레이스홀더: `알 수 없는 앨범 (2005-07-09 오후 12:48:43)`
        return placeholders.contains(key) || placeholders.contains { key.hasPrefix($0 + " (") }
    }

    private func isTitleEmpty(_ track: LibraryTrack, otherTextMissing: Bool) -> Bool {
        let title = Normalizer.clean(track.title)
        if title.isEmpty { return true }
        guard rules.treatPlaceholdersAsEmpty else { return false }
        let range = NSRange(title.startIndex..., in: title)
        if titlePatterns.contains(where: { $0.firstMatch(in: title, range: range) != nil }) {
            // 숫자만으로 된 제목(예: Britney Spears "3")은 실제 곡 제목일 수 있다. 가수·앨범도 함께 비어 있을 때만
            // 플레이스홀더로 본다. ('Track 3'·'트랙 5' 같은 접두어형은 가수·앨범이 있어도 플레이스홀더로 유지)
            if otherTextMissing || !title.allSatisfy(\.isNumber) { return true }
        }
        guard rules.treatFilenameLikeTitleAsEmpty, otherTextMissing,
              let stem = track.fileURL?.deletingPathExtension().lastPathComponent,
              Normalizer.clean(stem) == title
        else { return false }
        return Self.filenameLikeTitle.firstMatch(in: title, range: range) != nil
    }
}
