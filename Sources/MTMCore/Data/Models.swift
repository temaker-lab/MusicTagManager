import Foundation
import GRDB

/// 사용자가 고른 대상 플레이리스트
public struct SelectedPlaylistRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "selected_playlists"

    public var playlistPersistentID: String
    public var nameAtSelection: String
    public var isFolder: Bool
    public var isSmart: Bool
    public var selectedAt: Date
    public var lastCheckedAt: Date?
    public var lastTrackCount: Int?

    enum CodingKeys: String, CodingKey {
        case playlistPersistentID = "playlist_persistent_id"
        case nameAtSelection = "name_at_selection"
        case isFolder = "is_folder"
        case isSmart = "is_smart"
        case selectedAt = "selected_at"
        case lastCheckedAt = "last_checked_at"
        case lastTrackCount = "last_track_count"
    }

    public var id: PersistentID? { PersistentID(hex: playlistPersistentID) }
}

struct PlaylistTrackRecord: Codable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "playlist_tracks"

    var playlistPersistentID: String
    var persistentID: String

    enum CodingKeys: String, CodingKey {
        case playlistPersistentID = "playlist_persistent_id"
        case persistentID = "persistent_id"
    }
}

/// 선택 플레이리스트 범위의 곡 (전체 라이브러리 아님)
public struct TrackRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "tracks"

    public var persistentID: String
    public var completeness: Completeness
    public var missingFields: [RequiredField]
    public var filePath: String?
    public var fileExists: Bool
    public var title: String
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: Int
    public var trackNo: Int
    public var trackCount: Int
    public var discNo: Int
    public var discCount: Int
    public var durationMs: Int
    public var hasArtwork: Bool
    public var artworkWidth: Int?
    public var artworkHeight: Int?
    public var isCloudOnly: Bool
    public var isEligible: Bool
    public var albumGroupKey: String
    /// ITLibrary 수정 시각 (초, 정확한 왕복을 위해 REAL로 저장)
    public var modifiedAt: Double?
    /// 판정에 쓴 규칙 버전 (바뀌면 재검사)
    public var rulesVersion: String
    public var lastScannedAt: Date

    enum CodingKeys: String, CodingKey {
        case persistentID = "persistent_id"
        case completeness
        case missingFields = "missing_fields_json"
        case filePath = "file_path"
        case fileExists = "file_exists"
        case title, artist, album
        case albumArtist = "album_artist"
        case genre, year
        case trackNo = "track_no"
        case trackCount = "track_count"
        case discNo = "disc_no"
        case discCount = "disc_count"
        case durationMs = "duration_ms"
        case hasArtwork = "has_artwork"
        case artworkWidth = "artwork_width"
        case artworkHeight = "artwork_height"
        case isCloudOnly = "is_cloud_only"
        case isEligible = "is_eligible"
        case albumGroupKey = "album_group_key"
        case modifiedAt = "modified_at"
        case rulesVersion = "rules_version"
        case lastScannedAt = "last_scanned_at"
    }

    public init(track: LibraryTrack, result: CompletenessResult, fileExists: Bool, rulesVersion: String, scannedAt: Date) {
        persistentID = track.id.hex
        completeness = result.completeness
        missingFields = result.missing
        filePath = track.fileURL?.path
        self.fileExists = fileExists
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        genre = track.genre
        year = track.year
        trackNo = track.trackNumber
        trackCount = track.trackCount
        discNo = track.discNumber
        discCount = track.discCount
        durationMs = track.durationMs
        hasArtwork = track.hasArtwork
        isCloudOnly = track.isCloud && track.fileURL == nil
        isEligible = result.completeness.isEligible
        albumGroupKey = Self.albumGroupKey(for: track, missing: result.missing)
        modifiedAt = track.modifiedDate?.timeIntervalSince1970
        self.rulesVersion = rulesVersion
        lastScannedAt = scannedAt
    }

    /// 정규화된 (앨범 아티스트, 앨범). 앨범명이 비어 있는(플레이스홀더 포함) 곡은 단독 그룹
    public static func albumGroupKey(for track: LibraryTrack, missing: [RequiredField]) -> String {
        let album = Normalizer.compareKey(track.album)
        guard !album.isEmpty, !missing.contains(.album) else { return "single:\(track.id.hex)" }
        var artist = Normalizer.compareKey(track.albumArtist)
        if artist.isEmpty, !missing.contains(.artist) { artist = Normalizer.compareKey(track.artist) }
        return "\(artist)\u{1F}\(album)"
    }

    public var result: CompletenessResult { CompletenessResult(completeness, missing: missingFields) }

    /// 수정 시각이 바뀌지 않은 곡을 ITLibrary 대신 저장값으로 복원한다.
    public var libraryTrack: LibraryTrack {
        LibraryTrack(
            id: PersistentID(hex: persistentID) ?? PersistentID(0), title: title, artist: artist,
            albumArtist: albumArtist, album: album, genre: genre, year: year, trackNumber: trackNo,
            trackCount: trackCount, discNumber: discNo, discCount: discCount, durationMs: durationMs,
            hasArtwork: hasArtwork, fileURL: filePath.map { URL(fileURLWithPath: $0) }, isCloud: isCloudOnly,
            isSong: completeness != .excludedUnsupported, modifiedDate: modifiedAt.map(Date.init(timeIntervalSince1970:)))
    }
}

extension Completeness: DatabaseValueConvertible {}
