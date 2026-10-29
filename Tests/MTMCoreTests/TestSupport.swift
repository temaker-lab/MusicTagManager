import Foundation
@testable import MTMCore

/// 메모리 기반 라이브러리 (실제 Music 보관함 대신)
final class FakeLibrary: LibrarySource, @unchecked Sendable {
    var playlists: [LibraryPlaylist]
    var tracksByID: [PersistentID: LibraryTrack]

    init(playlists: [LibraryPlaylist] = [], tracks: [LibraryTrack] = []) {
        self.playlists = playlists
        self.tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    }

    var catalog: LibraryCatalog { LibraryCatalog(playlists: playlists) }

    func loadCatalog() async throws -> LibraryCatalog { catalog }

    /// 전체 변환을 요청받은 곡 수 (증분 재검사 검증용)
    private(set) var fullReads = 0

    func tracks(for ids: [PersistentID]) async -> [LibraryTrack] {
        fullReads += ids.count
        return ids.compactMap { tracksByID[$0] }
    }

    func modificationDates(for ids: [PersistentID]) async -> [PersistentID: Date] {
        var result: [PersistentID: Date] = [:]
        for id in ids { if let date = tracksByID[id]?.modifiedDate { result[id] = date } }
        return result
    }
}

func pid(_ value: UInt64) -> PersistentID { PersistentID(value) }

/// 4개 항목이 모두 채워진 곡
func completeTrack(_ id: UInt64, title: String = "Song", fileName: String? = nil) -> LibraryTrack {
    LibraryTrack(id: pid(id), title: title, artist: "Artist", album: "Album", hasArtwork: true,
                 fileURL: URL(fileURLWithPath: "/Music/Artist/Album/\(fileName ?? "01 \(title)").mp3"),
                 modifiedDate: Date(timeIntervalSince1970: 1_700_000_000))
}

let alwaysExists: (URL) -> Bool = { _ in true }
