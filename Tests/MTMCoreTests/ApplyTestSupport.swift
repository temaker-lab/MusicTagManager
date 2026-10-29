import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import MTMCore

/// 메모리 기반 Music 앱. 오류 주입으로 강제 종료·검증 실패를 흉내 낸다.
final class FakeMusic: MusicScripting, @unchecked Sendable {
    enum Operation { case write, setArtwork, deleteArtwork }

    private let lock = NSLock()
    private var tracks: [PersistentID: TrackFields]
    private var artworks: [PersistentID: [Data]] = [:]
    private(set) var operations: [(Operation, PersistentID)] = []
    var libraryCount = 100
    /// 쓰기를 무시하는 필드 (Music이 값을 저장하지 않는 상황)
    var ignoredFields: Set<ProposalField> = []
    /// 쓰기 전에 던질 오류
    var failBefore: ((Operation, PersistentID) -> Error?)?
    /// 쓰기를 반영한 뒤 던질 오류 (기록 전에 앱이 죽은 상황)
    var failAfter: ((Operation, PersistentID) -> Error?)?
    /// 쓰기 직전에 호출 (스냅샷 선행 확인용)
    var onWrite: ((PersistentID) -> Void)?

    init(_ tracks: [PersistentID: TrackFields]) {
        self.tracks = tracks
    }

    func fields(_ id: PersistentID) -> TrackFields? {
        lock.withLock {
            guard var fields = tracks[id] else { return nil }
            fields.artworkCount = artworks[id]?.count ?? 0
            return fields
        }
    }

    func edit(_ id: PersistentID, _ change: (inout TrackFields) -> Void) {
        lock.withLock { if var fields = tracks[id] { change(&fields); tracks[id] = fields } }
    }

    func setArtworkData(_ id: PersistentID, _ data: [Data]) { lock.withLock { artworks[id] = data } }
    func artworkList(_ id: PersistentID) -> [Data] { lock.withLock { artworks[id] ?? [] } }
    var writeCount: Int { lock.withLock { operations.count } }

    func readTracks(_ ids: [PersistentID]) async throws -> [PersistentID: TrackFields] {
        var result: [PersistentID: TrackFields] = [:]
        for id in ids { if let fields = fields(id) { result[id] = fields } }
        return result
    }

    func write(_ values: [String: FieldValue], to id: PersistentID) async throws {
        try perform(.write, id) {
            guard var fields = tracks[id] else { throw MusicScriptError(number: -1728, message: "") }
            for (key, value) in values {
                guard let field = ProposalField(rawValue: key), !ignoredFields.contains(field) else { continue }
                fields.set(field, value)
            }
            // 미디어 폴더 정리: 가수·앨범이 바뀌면 파일이 옮겨진다
            fields.location = "/Music/\(fields.artist)/\(fields.album)/\(fields.title).mp3"
            tracks[id] = fields
        }
    }

    func setArtwork(_ id: PersistentID, imageFile: URL) async throws {
        let data = try Data(contentsOf: imageFile)
        try perform(.setArtwork, id) {
            var list = artworks[id] ?? []
            if list.isEmpty { list.append(data) } else { list[0] = data }
            artworks[id] = list
        }
    }

    func deleteArtwork(_ id: PersistentID) async throws {
        try perform(.deleteArtwork, id) {
            if var list = artworks[id], !list.isEmpty { list.removeFirst(); artworks[id] = list }
        }
    }

    func artworkData(of id: PersistentID) async throws -> Data? { artworkList(id).first }

    func libraryTrackCount() async throws -> Int { libraryCount }

    private func perform(_ operation: Operation, _ id: PersistentID, _ body: () throws -> Void) throws {
        onWrite?(id)
        if let error = failBefore?(operation, id) { throw error }
        try lock.withLock {
            try body()
            operations.append((operation, id))
        }
        if let error = failAfter?(operation, id) { throw error }
    }
}

func makeJPEG(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func imageSize(_ data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mtm-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
