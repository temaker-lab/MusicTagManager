import Foundation

public struct PlaylistMembership: Hashable, Sendable {
    public let playlistID: PersistentID
    public let trackID: PersistentID

    public init(playlistID: PersistentID, trackID: PersistentID) {
        self.playlistID = playlistID
        self.trackID = trackID
    }
}

/// 선택한 플레이리스트가 실제로 가리키는 곡 집합
public struct ScopeResolution: Sendable {
    /// 중복 제거된 곡 ID (처음 등장한 순서)
    public let trackIDs: [PersistentID]
    /// 펼친 일반·스마트 플레이리스트와 곡의 관계 (playlist_tracks 테이블용)
    public let memberships: [PlaylistMembership]
    /// 폴더를 펼친 결과에 포함된 플레이리스트
    public let expandedPlaylists: [LibraryPlaylist]
    /// 여러 플레이리스트에 중복으로 들어 있어 한 번만 처리하게 된 횟수
    public let duplicatesRemoved: Int
}

public enum PlaylistScope {
    /// 저장된 선택 중 현재 보관함에 없는 플레이리스트(삭제됨)를 분리한다.
    public static func reconcile(selected: [PersistentID], in catalog: LibraryCatalog)
        -> (valid: [PersistentID], removed: [PersistentID]) {
        var valid: [PersistentID] = []
        var removed: [PersistentID] = []
        for id in selected {
            if catalog.playlist(id) != nil { valid.append(id) } else { removed.append(id) }
        }
        return (valid, removed)
    }

    /// 폴더는 하위 플레이리스트 전체(중첩 포함)로 펼친다.
    public static func expand(_ selection: [PersistentID], in catalog: LibraryCatalog) -> [LibraryPlaylist] {
        var seen = Set<PersistentID>()
        var result: [LibraryPlaylist] = []
        func visit(_ id: PersistentID) {
            guard seen.insert(id).inserted, let playlist = catalog.playlist(id) else { return }
            result.append(playlist)
            if playlist.isFolder {
                catalog.children(of: id).forEach { visit($0.id) }
            }
        }
        selection.forEach(visit)
        return result
    }

    /// 선택 범위의 곡을 persistentID 기준으로 한 번씩만 모은다.
    /// 폴더 자신의 항목은 하위 목록의 합집합이므로, 하위 플레이리스트가 있으면 그쪽에서만 곡을 센다.
    public static func resolve(_ selection: [PersistentID], in catalog: LibraryCatalog) -> ScopeResolution {
        let expanded = expand(selection, in: catalog)
        var seen = Set<PersistentID>()
        var ordered: [PersistentID] = []
        var memberships: [PlaylistMembership] = []
        var occurrences = 0
        for playlist in expanded {
            if playlist.isFolder && !catalog.children(of: playlist.id).isEmpty { continue }
            for trackID in playlist.itemIDs {
                occurrences += 1
                if !playlist.isFolder {
                    memberships.append(PlaylistMembership(playlistID: playlist.id, trackID: trackID))
                }
                if seen.insert(trackID).inserted { ordered.append(trackID) }
            }
        }
        return ScopeResolution(trackIDs: ordered, memberships: memberships, expandedPlaylists: expanded,
                               duplicatesRemoved: occurrences - ordered.count)
    }
}
