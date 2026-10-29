import Foundation

/// Music 라이브러리 항목(곡·플레이리스트)의 64비트 고유 ID.
/// ITLibrary는 `NSNumber`로, AppleScript `persistent ID`는 16자리 대문자 16진수 문자열로 표현한다.
public struct PersistentID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// ITLibrary의 `persistentID`. 부호 있는 값으로 담겨 와도 비트 패턴을 그대로 쓴다.
    public init(number: NSNumber) {
        self.rawValue = number.uint64Value
    }

    /// 정확히 16자리 16진수만 허용한다.
    /// Phase 0에서 AppleScript가 16자보다 긴 문자열도 다른 곡에 매칭시키는 것을 확인했으므로 엄격히 검증한다.
    public init?(hex: String) {
        guard hex.utf8.count == 16,
              hex.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }),
              let value = UInt64(hex, radix: 16)
        else { return nil }
        self.rawValue = value
    }

    /// AppleScript `persistent ID` 형식 (예: `BE2EBB05EA3BF7CE`)
    public var hex: String {
        let digits = String(rawValue, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    public var description: String { hex }

    public static func < (lhs: PersistentID, rhs: PersistentID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension PersistentID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let id = PersistentID(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "잘못된 persistent ID: \(string)")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
