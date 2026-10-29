import Foundation
import iTunesLibrary

/// 스캔에 필요한 라이브러리 읽기 인터페이스 (테스트에서는 메모리 구현으로 대체)
public protocol LibrarySource: Sendable {
    func loadCatalog() async throws -> LibraryCatalog
    func tracks(for ids: [PersistentID]) async -> [LibraryTrack]
    /// 증분 재검사용. 수정 시각은 싸게 읽히므로 이것만 먼저 비교한다.
    func modificationDates(for ids: [PersistentID]) async -> [PersistentID: Date]
}

public enum LibraryReaderError: LocalizedError {
    case unavailable(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let error):
            return "Music 보관함을 읽을 수 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 미디어 및 Apple Music에서 이 앱을 허용했는지 확인하세요. (\(error.localizedDescription))"
        }
    }
}

/// ITLibrary 래퍼. 읽기 전용이며 Music 앱에 Apple Event를 보내지 않는다.
public actor LibraryReader: LibrarySource {
    /// 곡 정보를 읽거나 판정하는 방식이 바뀌면 올린다 → 저장된 검사 결과를 한 번 전부 다시 판정
    /// (2: 커버 유무에 artwork 객체 확인, 3: 플레이스홀더 변형 인식)
    public static let trackFormatVersion = 3

    private var library: ITLibrary?
    private var itemsByID: [PersistentID: ITLibMediaItem] = [:]

    public init() {}

    /// 최신 상태의 플레이리스트 목록을 읽는다.
    /// 곡 정보는 여기서 만들지 않고, 필요한 범위만 `tracks(for:)`로 꺼낸다.
    public func loadCatalog() async throws -> LibraryCatalog {
        let library = try await reloadLibrary()
        var items: [PersistentID: ITLibMediaItem] = [:]
        var playlists: [LibraryPlaylist] = []
        for playlist in library.allPlaylists where playlist.isVisible || playlist.isMaster {
            let members = playlist.items
            var ids: [PersistentID] = []
            ids.reserveCapacity(members.count)
            for item in members {
                let id = PersistentID(number: item.persistentID)
                ids.append(id)
                if items[id] == nil { items[id] = item }
            }
            playlists.append(LibraryPlaylist(
                id: PersistentID(number: playlist.persistentID),
                parentID: playlist.parentID.map { PersistentID(number: $0) },
                name: playlist.name,
                kind: Self.kind(of: playlist),
                systemRole: Self.systemRole(of: playlist),
                itemIDs: ids
            ))
        }
        itemsByID = items
        Log.library.info("플레이리스트 \(playlists.count)개, 항목 \(items.count)개 로드")
        return LibraryCatalog(playlists: playlists)
    }

    public func tracks(for ids: [PersistentID]) async -> [LibraryTrack] {
        ids.compactMap { id in itemsByID[id].map { Self.makeTrack($0, id: id) } }
    }

    public func modificationDates(for ids: [PersistentID]) async -> [PersistentID: Date] {
        var result: [PersistentID: Date] = [:]
        result.reserveCapacity(ids.count)
        for id in ids {
            if let date = itemsByID[id]?.modifiedDate { result[id] = date }
        }
        return result
    }

    /// 보관함 전환 직후 등에는 보관함 서비스 연결이 일시적으로 실패한다(NSCocoaErrorDomain 4097) → 재시도
    private func reloadLibrary() async throws -> ITLibrary {
        if let library, library.reloadData() {
            return library
        }
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let library = try ITLibrary(apiVersion: "1.0")
                self.library = library
                return library
            } catch {
                lastError = error
                Log.library.error("ITLibrary 연결 실패 (\(attempt + 1)/4): \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
            }
        }
        throw LibraryReaderError.unavailable(underlying: lastError ?? CocoaError(.featureUnsupported))
    }

    private static func makeTrack(_ item: ITLibMediaItem, id: PersistentID) -> LibraryTrack {
        LibraryTrack(
            id: id,
            title: item.title,
            artist: item.artist?.name,
            albumArtist: item.album.albumArtist,
            album: item.album.title,
            genre: item.genre,
            year: item.year,
            trackNumber: item.trackNumber,
            trackCount: item.album.trackCount,
            discNumber: item.album.discNumber,
            discCount: item.album.discCount,
            durationMs: item.totalTime,
            // hasArtworkAvailable은 커버를 지운 뒤에도 true로 남는다(Phase 0·3 실측: 되돌리기 후 14곡 불일치).
            // artwork 객체까지 확인하면 AppleScript `count of artworks`와 일치한다.
            hasArtwork: item.hasArtworkAvailable && item.artwork != nil,
            fileURL: item.locationType == .file ? item.location : nil,
            isCloud: item.isCloud,
            isDRMProtected: item.isDRMProtected,
            isSong: item.mediaKind == .kindSong,
            modifiedDate: item.modifiedDate
        )
    }

    private static func kind(of playlist: ITLibPlaylist) -> PlaylistKind {
        switch playlist.kind {
        case .regular: return .regular
        case .smart: return .smart
        case .folder: return .folder
        default: return .other
        }
    }

    private static func systemRole(of playlist: ITLibPlaylist) -> SystemPlaylistRole? {
        if playlist.isMaster { return .library }
        switch playlist.distinguishedKind {
        case .kindNone: return nil
        case .kindMusic: return .music
        default: return .other
        }
    }
}
