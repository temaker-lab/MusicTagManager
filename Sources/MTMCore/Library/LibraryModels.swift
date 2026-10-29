import Foundation

public enum PlaylistKind: String, Sendable, Codable {
    case regular, smart, folder, other
}

/// 시스템이 만든 플레이리스트의 역할. 사용자 플레이리스트는 nil.
public enum SystemPlaylistRole: String, Sendable, Codable {
    /// 보관함(마스터) — 전체 라이브러리
    case library
    /// '음악' 기본 목록
    case music
    /// 동영상·오디오북 등 그 밖의 기본 목록
    case other
}

public struct LibraryPlaylist: Identifiable, Hashable, Sendable {
    public let id: PersistentID
    public let parentID: PersistentID?
    public let name: String
    public let kind: PlaylistKind
    public let systemRole: SystemPlaylistRole?
    /// 플레이리스트에 담긴 항목 ID (폴더는 하위 플레이리스트 합집합)
    public let itemIDs: [PersistentID]

    public init(id: PersistentID, parentID: PersistentID? = nil, name: String, kind: PlaylistKind = .regular,
                systemRole: SystemPlaylistRole? = nil, itemIDs: [PersistentID]) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.kind = kind
        self.systemRole = systemRole
        self.itemIDs = itemIDs
    }

    public var isFolder: Bool { kind == .folder }
    public var isSmart: Bool { kind == .smart }
}

/// ITLibrary 항목에서 필요한 값만 뽑아낸 값 타입 (스레드 간 전달·테스트용)
public struct LibraryTrack: Identifiable, Hashable, Sendable {
    public let id: PersistentID
    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var year: Int
    public var trackNumber: Int
    public var trackCount: Int
    public var discNumber: Int
    public var discCount: Int
    public var durationMs: Int
    public var hasArtwork: Bool
    /// 로컬 파일 위치 (스트리밍·클라우드 전용 곡은 nil)
    public var fileURL: URL?
    public var isCloud: Bool
    /// FairPlay DRM으로 보호된 곡 (예: 옛 iTunes .m4p). 오디오 지문을 만들 수 없다.
    public var isDRMProtected: Bool
    /// 음악 곡 여부 (뮤직비디오·팟캐스트 등은 false)
    public var isSong: Bool
    /// Music이 기록한 마지막 수정 시각. 증분 재검사의 기준
    public var modifiedDate: Date?

    public init(id: PersistentID, title: String = "", artist: String? = nil, albumArtist: String? = nil,
                album: String? = nil, genre: String? = nil, year: Int = 0, trackNumber: Int = 0,
                trackCount: Int = 0, discNumber: Int = 0, discCount: Int = 0, durationMs: Int = 0,
                hasArtwork: Bool = false, fileURL: URL? = nil, isCloud: Bool = false, isDRMProtected: Bool = false,
                isSong: Bool = true, modifiedDate: Date? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.trackCount = trackCount
        self.discNumber = discNumber
        self.discCount = discCount
        self.durationMs = durationMs
        self.hasArtwork = hasArtwork
        self.fileURL = fileURL
        self.isCloud = isCloud
        self.isDRMProtected = isDRMProtected
        self.isSong = isSong
        self.modifiedDate = modifiedDate
    }
}

/// 한 시점의 플레이리스트 목록
public struct LibraryCatalog: Sendable {
    public let playlists: [LibraryPlaylist]
    public let loadedAt: Date
    private let indexByID: [PersistentID: Int]
    private let childIDsByParent: [PersistentID: [PersistentID]]

    public init(playlists: [LibraryPlaylist], loadedAt: Date = Date()) {
        self.playlists = playlists
        self.loadedAt = loadedAt
        var index: [PersistentID: Int] = [:]
        var children: [PersistentID: [PersistentID]] = [:]
        for (offset, playlist) in playlists.enumerated() {
            index[playlist.id] = offset
            if let parent = playlist.parentID {
                children[parent, default: []].append(playlist.id)
            }
        }
        self.indexByID = index
        self.childIDsByParent = children
    }

    public func playlist(_ id: PersistentID) -> LibraryPlaylist? {
        indexByID[id].map { playlists[$0] }
    }

    public func children(of id: PersistentID) -> [LibraryPlaylist] {
        (childIDsByParent[id] ?? []).compactMap(playlist)
    }

    /// 사용자가 만든 플레이리스트·폴더
    public var userPlaylists: [LibraryPlaylist] {
        playlists.filter { $0.systemRole == nil }
    }

    /// 부모를 따라 올라가며 조상 ID를 반환한다 (가까운 순)
    public func ancestors(of id: PersistentID) -> [PersistentID] {
        var result: [PersistentID] = []
        var current = playlist(id)?.parentID
        while let parent = current, !result.contains(parent) {
            result.append(parent)
            current = playlist(parent)?.parentID
        }
        return result
    }
}
