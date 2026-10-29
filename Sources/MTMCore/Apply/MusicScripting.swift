import Foundation

/// Music 앱 명령. 실제 구현은 AppleScript, 테스트에서는 메모리 구현.
/// 앱에서는 `LibraryWriter`만 쓰기 명령을 호출한다.
public protocol MusicScripting: Sendable {
    /// 없는 곡은 결과에서 빠진다
    func readTracks(_ ids: [PersistentID]) async throws -> [PersistentID: TrackFields]
    func write(_ values: [String: FieldValue], to id: PersistentID) async throws
    /// 커버 1번을 이 이미지(JPEG)로 설정
    func setArtwork(_ id: PersistentID, imageFile: URL) async throws
    func deleteArtwork(_ id: PersistentID) async throws
    /// 커버 1번의 원본 바이트 (없으면 nil)
    func artworkData(of id: PersistentID) async throws -> Data?
    func libraryTrackCount() async throws -> Int
}

public struct MusicScriptError: LocalizedError, Equatable {
    public let number: Int
    public let message: String

    public var errorDescription: String? {
        switch number {
        case -1743: return "Music 앱 제어 권한이 없습니다 (시스템 설정 > 개인정보 보호 및 보안 > 자동화)"
        case -1728: return "Music 보관함에서 곡을 찾을 수 없습니다"
        case -1712: return "Music 앱이 응답하지 않습니다 (시간 초과)"
        default: return "Music 앱 오류 \(number): \(message)"
        }
    }

    /// 다시 시도해도 소용없는 오류
    public var isPermanent: Bool { [-1743, -1728, -1708, -10006].contains(number) }
}

/// AppleScript 구현. 곡은 persistent ID로만 찾는다 (형식은 PersistentID에서 검증됨).
public final class AppleScriptMusic: MusicScripting {
    private let runner = AppleScriptRunner()

    public init() {}

    static func ref(_ id: PersistentID) -> String {
        "(first track of library playlist 1 whose persistent ID is \"\(id.hex)\")"
    }

    static let properties: [ProposalField: String] = [
        .title: "name", .artist: "artist", .album: "album", .albumArtist: "album artist", .genre: "genre",
        .year: "year", .trackNumber: "track number", .trackCount: "track count",
        .discNumber: "disc number", .discCount: "disc count",
    ]

    /// AppleScript 문자열 리터럴
    static func literal(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        return "\"" + cleaned.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public func readTracks(_ ids: [PersistentID]) async throws -> [PersistentID: TrackFields] {
        var result: [PersistentID: TrackFields] = [:]
        // 묶음이 크면 메인 스레드를 오래 잡으므로 10곡씩
        for chunk in stride(from: 0, to: ids.count, by: 10).map({ Array(ids[$0..<min($0 + 10, ids.count)]) }) {
            let list = "{" + chunk.map { "\"\($0.hex)\"" }.joined(separator: ", ") + "}"
            let source = """
            tell application "Music"
              with timeout of 60 seconds
                set out to {}
                repeat with p in \(list)
                  try
                    set t to (first track of library playlist 1 whose persistent ID is (p as text))
                    set loc to ""
                    try
                      set loc to POSIX path of (get location of t)
                    end try
                    set end of out to {p as text, name of t, artist of t, album of t, album artist of t, genre of t, year of t, track number of t, track count of t, disc number of t, disc count of t, (count of artworks of t), loc}
                  on error number -1728
                    set end of out to {p as text}
                  end try
                end repeat
                return out
              end timeout
            end tell
            """
            let rows = try await runner.run(source) { descriptor -> [(String, TrackFields?)] in
                (0..<descriptor.numberOfItems).compactMap { index in
                    guard let row = descriptor.atIndex(index + 1), let pid = row.atIndex(1)?.stringValue else { return nil }
                    guard row.numberOfItems >= 13 else { return (pid, nil) }
                    func text(_ i: Int) -> String { row.atIndex(i)?.stringValue ?? "" }
                    func number(_ i: Int) -> Int { Int(row.atIndex(i)?.int32Value ?? 0) }
                    var fields = TrackFields()
                    fields.title = text(2)
                    fields.artist = text(3)
                    fields.album = text(4)
                    fields.albumArtist = text(5)
                    fields.genre = text(6)
                    fields.year = number(7)
                    fields.trackNumber = number(8)
                    fields.trackCount = number(9)
                    fields.discNumber = number(10)
                    fields.discCount = number(11)
                    fields.artworkCount = number(12)
                    let location = text(13)
                    fields.location = location.isEmpty ? nil : location
                    return (pid, fields)
                }
            }
            for (hex, fields) in rows {
                if let id = PersistentID(hex: hex), let fields { result[id] = fields }
            }
        }
        return result
    }

    public func write(_ values: [String: FieldValue], to id: PersistentID) async throws {
        let lines = values.sorted { $0.key < $1.key }.compactMap { key, value -> String? in
            guard let field = ProposalField(rawValue: key), let property = Self.properties[field] else { return nil }
            switch value {
            case .text(let text): return "    set \(property) of t to \(Self.literal(text))"
            case .number(let number): return "    set \(property) of t to \(number)"
            }
        }
        guard !lines.isEmpty else { return }
        try await runVoid("""
        tell application "Music"
          with timeout of 30 seconds
            set t to \(Self.ref(id))
        \(lines.joined(separator: "\n"))
          end timeout
        end tell
        """)
    }

    public func setArtwork(_ id: PersistentID, imageFile: URL) async throws {
        try await runVoid("""
        set img to read (POSIX file \(Self.literal(imageFile.path))) as JPEG picture
        tell application "Music"
          with timeout of 30 seconds
            set data of artwork 1 of \(Self.ref(id)) to img
          end timeout
        end tell
        """)
    }

    public func deleteArtwork(_ id: PersistentID) async throws {
        try await runVoid("""
        tell application "Music"
          with timeout of 30 seconds
            delete artwork 1 of \(Self.ref(id))
          end timeout
        end tell
        """)
    }

    public func artworkData(of id: PersistentID) async throws -> Data? {
        try await runner.run("""
        tell application "Music"
          with timeout of 30 seconds
            set t to \(Self.ref(id))
            if (count of artworks of t) is 0 then return ""
            return raw data of artwork 1 of t
          end timeout
        end tell
        """) { descriptor in
            descriptor.descriptorType == typeUnicodeText || descriptor.data.isEmpty ? nil : descriptor.data
        }
    }

    public func libraryTrackCount() async throws -> Int {
        try await runner.run("tell application \"Music\" to count tracks of library playlist 1") { Int($0.int32Value) }
    }

    private func runVoid(_ source: String) async throws {
        _ = try await runner.run(source) { _ in true }
    }
}

/// NSAppleScript는 메인 스레드에서 순서대로 실행한다.
/// 백그라운드 스레드에서 실행하면 Music의 응답 이벤트를 받지 못해 영원히 기다린다
/// (Phase 3 실측: `AEDefaultActiveProc → GetNextEventMatchingMask`에서 정지). 한 번에 한 곡만 다뤄 UI 정지는 짧게 유지한다.
final class AppleScriptRunner: Sendable {
    func run<T: Sendable>(_ source: String, parse: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: MusicScriptError(number: -2700, message: "스크립트 생성 실패"))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    continuation.resume(throwing: MusicScriptError(
                        number: error[NSAppleScript.errorNumber] as? Int ?? -1,
                        message: error[NSAppleScript.errorMessage] as? String ?? ""))
                    return
                }
                do {
                    continuation.resume(returning: try parse(result))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
