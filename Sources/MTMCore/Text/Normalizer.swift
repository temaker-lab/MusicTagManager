import Foundation

/// 문자열 비교 전 정규화.
/// macOS 파일 경로와 일부 태그는 한글을 NFD(자모 분리)로 저장하므로 모든 비교는 NFC로 맞춘 뒤 한다.
public enum Normalizer {
    /// NFC 정규화 + 앞뒤 공백(전각 공백 포함) 제거
    public static func clean(_ value: String?) -> String {
        guard let value else { return "" }
        return value.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 비교용 키: `clean` + 대소문자 무시 + 연속 공백을 하나로
    public static func compareKey(_ value: String?) -> String {
        clean(value)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let bracketed = try! NSRegularExpression(pattern: #"[\(\[\{（【「〈<][^\)\]\}）】」〉>]*[\)\]\}）】」〉>]"#)
    private static let featuring = try! NSRegularExpression(pattern: #"\s(feat\.?|ft\.|featuring|prod\.?|prod by)\s.*$"#)

    /// 곡·앨범 매칭용 키: 괄호 속 표기(feat., Inst., Remastered 등)와 본문 뒤 feat./Prod. 구간, 문장부호·공백을 모두 뺀다.
    /// 예: `사랑에 아파한 날들 (Feat. 윤하)` → `사랑에아파한날들`
    public static func matchKey(_ value: String?) -> String {
        let base = compareKey(value)
        var stripped = replace(bracketed, in: base, with: " ")
        stripped = replace(featuring, in: stripped, with: "")
        let key = lettersAndDigits(stripped)
        // 제목 전체가 괄호인 경우(예: `(Intro)`)에는 괄호 안 내용을 쓴다
        return key.isEmpty ? lettersAndDigits(base) : key
    }

    /// 매칭에서 구분해야 하는 버전 표기. 원곡과 Inst./Live/Remix가 섞이지 않게 한다.
    public enum VersionTag: String, CaseIterable, Sendable {
        case instrumental, live, remix, acoustic, acappella
    }

    public static func versionTags(_ value: String?) -> Set<VersionTag> {
        let key = compareKey(value)
        var tags = Set<VersionTag>()
        if key.range(of: #"\b(inst\.?|instrumental|mr)\b|반주"#, options: .regularExpression) != nil { tags.insert(.instrumental) }
        if key.range(of: #"\blive\b|라이브"#, options: .regularExpression) != nil { tags.insert(.live) }
        if key.range(of: #"\bremix(ed)?\b|\bmix by\b"#, options: .regularExpression) != nil { tags.insert(.remix) }
        if key.range(of: #"\b(acoustic|unplugged)\b|어쿠스틱"#, options: .regularExpression) != nil { tags.insert(.acoustic) }
        if key.range(of: #"\ba ?cc?app?ella\b|아카펠라"#, options: .regularExpression) != nil { tags.insert(.acappella) }
        return tags
    }

    /// 가수명 변형: `아이유(IU)` → [`아이유(IU)`, `아이유`, `IU`], `A feat. B` → [`A feat. B`, `A`]
    public static func artistNameVariants(_ value: String?) -> [String] {
        let name = clean(value)
        guard !name.isEmpty else { return [] }
        var variants = [name]
        if let match = name.range(of: #"^(.+?)\s*[\(（](.+?)[\)）]\s*$"#, options: .regularExpression), match == name.startIndex..<name.endIndex,
           let open = name.firstIndex(where: { $0 == "(" || $0 == "（" }) {
            variants.append(clean(String(name[..<open])))
            variants.append(clean(String(name[name.index(after: open)...].dropLast())))
        }
        let primary = name.replacingOccurrences(
            of: #"\s*(\bfeat\.?|\bft\.|\bfeaturing|\bwith\b|&|;|,|/|\s[xX×]\s).*$"#, with: "", options: .regularExpression)
        variants.append(clean(primary))
        var seen = Set<String>()
        return variants.filter { !$0.isEmpty && seen.insert(compareKey($0)).inserted }
    }

    /// 0...1 유사도 (매칭 키의 정규화 편집 거리). 어느 한쪽이 비면 0
    /// 검색어 변형: 기호 앞뒤 띄어쓰기가 데이터베이스와 다르면 검색 엔진이 다른 단어로 나눈다
    /// (예: 보관함 `2 + 1` ↔ MusicBrainz `2+1`). 원래 값 → 기호 앞뒤 공백 제거 → 기호를 공백으로 바꾼 값 순서.
    public static func searchVariants(_ value: String?) -> [String] {
        let base = clean(value)
        guard !base.isEmpty else { return [] }
        let symbol = #"[^\p{L}\p{N}\s]"#
        let joined = base.replacingOccurrences(of: #"\s*("# + symbol + #")\s*"#, with: "$1", options: .regularExpression)
        let spaced = base.replacingOccurrences(of: symbol, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result: [String] = []
        for variant in [base, joined, spaced] where !variant.isEmpty && !result.contains(variant) {
            result.append(variant)
        }
        return result
    }

    public static func similarity(_ lhs: String?, _ rhs: String?) -> Double {
        keySimilarity(matchKey(lhs), matchKey(rhs))
    }

    /// 가수명 유사도: 양쪽 변형 중 가장 비슷한 쌍 (`아이유(IU)` ↔ `IU` = 1.0)
    public static func artistSimilarity(_ lhs: String?, _ rhs: String?) -> Double {
        let left = artistNameVariants(lhs).map(matchKey)
        let right = artistNameVariants(rhs).map(matchKey)
        var best = 0.0
        for a in left {
            for b in right {
                best = max(best, keySimilarity(a, b))
            }
        }
        return best
    }

    public static func containsHangul(_ value: String?) -> Bool {
        (value ?? "").unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
    }

    static func keySimilarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                current[j] = x[i - 1] == y[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    private static func replace(_ regex: NSRegularExpression, in value: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: template)
    }

    private static func lettersAndDigits(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}
