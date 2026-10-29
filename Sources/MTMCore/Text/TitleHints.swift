import Foundation

/// 파일명 형태의 제목에서 뽑은 검색 단서.
/// 예: `Toto - Africa`, `05 Make It Happen`, `1-04 Someone`, `Abu&Noreen - 09 - Tao delicado`,
/// `T-Square - EXCITING PEACE - 02 - Dandelion Hill`(가수 - 앨범 - 번호 - 제목)
public struct TitleHints: Equatable, Sendable {
    public var artist: String?
    public var album: String?
    public var title: String
    public var trackNumber: Int?
    public var discNumber: Int?

    public init(artist: String? = nil, album: String? = nil, title: String, trackNumber: Int? = nil, discNumber: Int? = nil) {
        self.artist = artist
        self.album = album
        self.title = title
        self.trackNumber = trackNumber
        self.discNumber = discNumber
    }

    private static let discTrackPrefix = try! NSRegularExpression(pattern: #"^(\d{1,2})-(\d{1,3})[\s._-]+(.+)$"#)
    private static let trackPrefix = try! NSRegularExpression(pattern: #"^(\d{1,3})[\s._-]+(.+)$"#)
    private static let artistTrackTitle = try! NSRegularExpression(pattern: #"^(.+?)\s+-\s+(\d{1,3})\s+-\s+(.+)$"#)
    private static let artistTitle = try! NSRegularExpression(pattern: #"^(.+?)\s+-\s+(.+)$"#)

    /// 단서를 찾지 못하면 nil (제목을 그대로 쓰면 된다)
    public static func parse(_ raw: String?) -> TitleHints? {
        var rest = Normalizer.clean(raw)
        guard !rest.isEmpty else { return nil }
        var hints = TitleHints(title: rest)
        var found = false

        if let groups = match(discTrackPrefix, rest) {
            hints.discNumber = Int(groups[0])
            hints.trackNumber = Int(groups[1])
            rest = groups[2]
            found = true
        } else if let groups = match(trackPrefix, rest) {
            hints.trackNumber = Int(groups[0])
            rest = groups[1]
            found = true
        }

        if let groups = match(artistTrackTitle, rest) {
            // `가수 - 앨범 - 번호 - 제목`이면 앞부분을 가수와 앨범으로 나눈다
            if let split = match(artistTitle, groups[0]) {
                hints.artist = split[0]
                hints.album = split[1]
            } else {
                hints.artist = groups[0]
            }
            hints.trackNumber = hints.trackNumber ?? Int(groups[1])
            rest = groups[2]
            found = true
        } else if let groups = match(artistTitle, rest) {
            hints.artist = groups[0]
            rest = groups[1]
            found = true
        }

        hints.title = Normalizer.clean(rest)
        return found && !hints.title.isEmpty ? hints : nil
    }

    private static func match(_ regex: NSRegularExpression, _ value: String) -> [String]? {
        guard let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: value).map { Normalizer.clean(String(value[$0])) } ?? ""
        }
    }
}
