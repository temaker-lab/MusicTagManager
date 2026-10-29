import Foundation
import GRDB

/// 앱 데이터베이스 (GRDB). 마이그레이션은 버전별로 추가만 한다.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// ~/Library/Application Support/MusicTagManager/mtm.sqlite
    public static func openDefault() throws -> AppDatabase {
        try open(at: defaultDirectory.appendingPathComponent("mtm.sqlite"))
    }

    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabaseQueue(path: url.path))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicTagManager", isDirectory: true)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_library_scope") { db in
            try db.create(table: "selected_playlists") { t in
                t.primaryKey("playlist_persistent_id", .text)
                t.column("name_at_selection", .text).notNull()
                t.column("is_folder", .boolean).notNull()
                t.column("is_smart", .boolean).notNull()
                t.column("selected_at", .datetime).notNull()
                t.column("last_checked_at", .datetime)
                t.column("last_track_count", .integer)
            }
            try db.create(table: "playlist_tracks") { t in
                t.column("playlist_persistent_id", .text).notNull()
                t.column("persistent_id", .text).notNull()
                t.primaryKey(["playlist_persistent_id", "persistent_id"])
            }
            try db.create(table: "tracks") { t in
                t.primaryKey("persistent_id", .text)
                t.column("completeness", .text).notNull()
                t.column("missing_fields_json", .text).notNull()
                t.column("file_path", .text)
                t.column("file_exists", .boolean).notNull()
                t.column("title", .text).notNull()
                t.column("artist", .text)
                t.column("album", .text)
                t.column("album_artist", .text)
                t.column("genre", .text)
                t.column("year", .integer).notNull()
                t.column("track_no", .integer).notNull()
                t.column("track_count", .integer).notNull()
                t.column("disc_no", .integer).notNull()
                t.column("disc_count", .integer).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("has_artwork", .boolean).notNull()
                t.column("artwork_width", .integer)
                t.column("artwork_height", .integer)
                t.column("is_cloud_only", .boolean).notNull()
                t.column("is_eligible", .boolean).notNull().indexed()
                t.column("album_group_key", .text).notNull().indexed()
                t.column("modified_at", .double)
                t.column("rules_version", .text).notNull()
                t.column("last_scanned_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_identification") { db in
            try db.create(table: "api_cache") { t in
                t.primaryKey("key", .text)
                t.column("provider", .text).notNull()
                t.column("response_json", .text).notNull()
                t.column("fetched_at", .datetime).notNull()
            }
            try db.create(table: "albums_resolved") { t in
                t.primaryKey("album_group_key", .text)
                t.column("source", .text).notNull()
                t.column("external_release_id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("album_artist", .text)
                t.column("year", .integer)
                t.column("genre", .text)
                t.column("track_count", .integer)
                t.column("disc_count", .integer)
                t.column("artwork_url", .text)
                t.column("artwork_width", .integer)
                t.column("confidence_score", .integer).notNull()
                t.column("confidence_level", .text).notNull()
                t.column("alternatives_json", .text).notNull()  // 다른 후보 릴리스 (앨범 상세에서 선택 변경용)
                t.column("resolved_at", .datetime).notNull()
            }
            try db.create(table: "proposals") { t in
                t.primaryKey("persistent_id", .text)
                t.column("album_group_key", .text).notNull().indexed()
                t.column("title", .text)
                t.column("artist", .text)
                t.column("album", .text)
                t.column("album_artist", .text)
                t.column("genre", .text)
                t.column("year", .integer)
                t.column("track_no", .integer)
                t.column("track_count", .integer)
                t.column("disc_no", .integer)
                t.column("disc_count", .integer)
                t.column("artwork_ref", .text)
                t.column("artwork_candidates_json", .text).notNull().defaults(to: "[]")
                t.column("source", .text)
                t.column("external_release_id", .text)
                t.column("external_recording_id", .text)
                t.column("isrc", .text)
                t.column("field_status_json", .text).notNull()
                t.column("evidence_json", .text).notNull()  // 점수 근거 (검토 화면 설명용)
                t.column("confidence_score", .integer).notNull()
                t.column("confidence_level", .text).notNull().indexed()
                t.column("blocks_auto_apply", .boolean).notNull()
                t.column("decision", .text).notNull().indexed()
                t.column("final_values_json", .text)
                t.column("track_modified_at", .double)  // 식별 당시 곡 수정 시각 (바뀌면 재식별)
                t.column("identified_at", .datetime).notNull()
            }
        }
        registerApplyMigration(&migrator)
        migrator.registerMigration("v4_proposal_missing") { db in
            try db.alter(table: "proposals") { t in
                t.add(column: "missing_fields_json", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v5_artwork_checks") { db in
            try db.create(table: "artwork_checks") { t in
                t.primaryKey("candidate", .text)
                t.column("usable", .boolean).notNull()
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("reason", .text)
                t.column("checked_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v6_file_backup") { db in
            try db.alter(table: "snapshots") { t in
                t.add(column: "before_file_path", .text)
            }
        }
        migrator.registerMigration("v7_artwork_truth") { db in
            // ITLibrary는 곡에 커버가 없어도 같은 앨범의 캐시 이미지를 돌려줄 때가 있다 → Music에서 읽은 실제 값을 기억
            try db.create(table: "artwork_truth") { t in
                t.primaryKey("persistent_id", .text)
                t.column("has_artwork", .boolean).notNull()
                t.column("recorded_at", .datetime).notNull()
            }
        }
        return migrator
    }

    // MARK: - 대상 플레이리스트

    public func selectedPlaylists() throws -> [SelectedPlaylistRecord] {
        try writer.read { db in
            try SelectedPlaylistRecord.order(Column("selected_at"), Column("playlist_persistent_id")).fetchAll(db)
        }
    }

    public func selectedPlaylistIDs() throws -> [PersistentID] {
        try selectedPlaylists().compactMap(\.id)
    }

    /// 선택을 교체한다. 계속 선택된 항목은 처음 선택 시각·이름을 유지한다.
    public func replaceSelection(_ playlists: [LibraryPlaylist], at date: Date = Date()) throws {
        try writer.write { db in
            let existing = try SelectedPlaylistRecord.fetchAll(db)
            let keep = Set(playlists.map(\.id.hex))
            for record in existing where !keep.contains(record.playlistPersistentID) {
                try record.delete(db)
                try PlaylistTrackRecord.filter(Column("playlist_persistent_id") == record.playlistPersistentID).deleteAll(db)
            }
            let existingIDs = Set(existing.map(\.playlistPersistentID))
            for playlist in playlists where !existingIDs.contains(playlist.id.hex) {
                try SelectedPlaylistRecord(
                    playlistPersistentID: playlist.id.hex, nameAtSelection: playlist.name,
                    isFolder: playlist.isFolder, isSmart: playlist.isSmart, selectedAt: date
                ).insert(db)
            }
        }
    }

    // MARK: - 커버 실제 상태

    /// Music(AppleScript `count of artworks`)에서 읽은 실제 커버 유무
    public func recordArtworkTruth(_ values: [PersistentID: Bool], at date: Date = Date()) throws {
        guard !values.isEmpty else { return }
        try writer.write { db in
            for (id, hasArtwork) in values {
                try db.execute(sql: "INSERT OR REPLACE INTO artwork_truth (persistent_id, has_artwork, recorded_at) VALUES (?, ?, ?)",
                               arguments: [id.hex, hasArtwork, date])
            }
        }
    }

    public func artworkTruth() throws -> [String: (hasArtwork: Bool, recordedAt: Date)] {
        try writer.read { db in
            var result: [String: (Bool, Date)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT persistent_id, has_artwork, recorded_at FROM artwork_truth") {
                result[row["persistent_id"]] = (row["has_artwork"], row["recorded_at"])
            }
            return result
        }
    }

    /// 작업 이력·스냅샷·식별 결과를 모두 지운다 (플레이리스트를 바꿀 때). 이전 변경은 더 이상 되돌릴 수 없다.
    public func clearHistory() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM snapshots")
            try db.execute(sql: "DELETE FROM apply_results")
            try db.execute(sql: "DELETE FROM jobs")
            try db.execute(sql: "DELETE FROM proposals")
            try db.execute(sql: "DELETE FROM albums_resolved")
        }
    }

    // MARK: - 스캔 결과

    func storedTracks() throws -> [PersistentID: TrackRecord] {
        try writer.read { db in
            var result: [PersistentID: TrackRecord] = [:]
            for record in try TrackRecord.fetchAll(db) {
                if let id = PersistentID(hex: record.persistentID) { result[id] = record }
            }
            return result
        }
    }

    public func trackRecords() throws -> [TrackRecord] {
        try writer.read { db in try TrackRecord.fetchAll(db) }
    }

    func playlistTrackCount() throws -> Int {
        try writer.read { db in try PlaylistTrackRecord.fetchCount(db) }
    }

    /// 한 트랜잭션으로 스캔 결과를 반영한다: 바뀐 곡만 기록, 범위를 벗어난 곡 삭제, 플레이리스트↔곡 관계 차분 반영
    func persistScan(changed: [TrackRecord], scopeIDs: Set<String>, memberships: [PlaylistMembership],
                     removedSelections: [PersistentID], selectionCounts: [PersistentID: Int], at date: Date) throws {
        try writer.write { db in
            for id in removedSelections {
                _ = try SelectedPlaylistRecord.deleteOne(db, key: id.hex)
            }
            for record in changed {
                try record.upsert(db)
            }
            let storedIDs = try String.fetchAll(db, sql: "SELECT persistent_id FROM tracks")
            let outOfScope = storedIDs.filter { !scopeIDs.contains($0) }
            if !outOfScope.isEmpty {
                try TrackRecord.deleteAll(db, keys: outOfScope)
            }

            let wanted = Set(memberships.map {
                PlaylistTrackRecord(playlistPersistentID: $0.playlistID.hex, persistentID: $0.trackID.hex)
            })
            let current = Set(try PlaylistTrackRecord.fetchAll(db))
            for record in current.subtracting(wanted) { try record.delete(db) }
            for record in wanted.subtracting(current) { try record.insert(db) }

            for (id, count) in selectionCounts {
                try db.execute(
                    sql: "UPDATE selected_playlists SET last_checked_at = ?, last_track_count = ? WHERE playlist_persistent_id = ?",
                    arguments: [date, count, id.hex])
            }
        }
    }
}
