import Foundation
import GRDB

/// 제안 필드 (필수 4개 + 보조 필드)
public enum ProposalField: String, CaseIterable, Codable, Sendable {
    case title, artist, album, albumArtist, genre, year, trackNumber, trackCount, discNumber, discCount, artwork

    public var label: String {
        switch self {
        case .title: return MTMLoc.t("field.title", "곡 제목")
        case .artist: return MTMLoc.t("field.artist", "가수명")
        case .album: return MTMLoc.t("field.album", "앨범명")
        case .albumArtist: return MTMLoc.t("field.albumArtist", "앨범 아티스트")
        case .genre: return MTMLoc.t("field.genre", "장르")
        case .year: return MTMLoc.t("field.year", "연도")
        case .trackNumber: return MTMLoc.t("field.trackNumber", "트랙 번호")
        case .trackCount: return MTMLoc.t("field.trackCount", "트랙 수")
        case .discNumber: return MTMLoc.t("field.discNumber", "디스크 번호")
        case .discCount: return MTMLoc.t("field.discCount", "디스크 수")
        case .artwork: return MTMLoc.t("field.artwork", "앨범커버")
        }
    }
}

public enum FieldStatus: String, Codable, Sendable {
    /// 현재 값과 같음
    case unchanged = "UNCHANGED"
    /// 현재 값과 다름 (비어 있던 칸을 채우는 경우 포함)
    case changed = "CHANGED"
    /// 제안 값 없음
    case noMatch = "NO_MATCH"
}

public enum ProposalDecision: String, Codable, Sendable {
    case pending = "PENDING"
    case autoApproved = "AUTO_APPROVED"
    case userApproved = "USER_APPROVED"
    case userOverride = "USER_OVERRIDE"
    case rejected = "REJECTED"
    /// 채울 값이 없음 (기록만)
    case skipped = "SKIPPED"
}

/// 곡 단위 제안값
public struct ProposalRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "proposals"

    public var persistentID: String
    public var albumGroupKey: String
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: Int?
    public var trackNo: Int?
    public var trackCount: Int?
    public var discNo: Int?
    public var discCount: Int?
    /// 1순위 커버: `track:<pid>`(같은 앨범 곡의 커버) · `itunes:<url>` · `caa:<url>`
    public var artworkRef: String?
    /// 커버 후보 전체 (적용 단계에서 순서대로 내려받아 검증)
    public var artworkCandidates: [String] = []
    public var source: ProviderID?
    public var externalReleaseID: String?
    public var externalRecordingID: String?
    public var isrc: String?
    public var fieldStatus: [String: FieldStatus]
    public var evidence: ProposalEvidence
    public var confidenceScore: Int
    public var confidenceLevel: ConfidenceLevel
    public var blocksAutoApply: Bool
    public var decision: ProposalDecision
    public var finalValuesJSON: String?
    public var trackModifiedAt: Double?
    public var identifiedAt: Date
    /// 식별 당시 비어 있던 필수 항목 (달라지면 다시 식별)
    public var missingAtIdentification: [RequiredField] = []

    enum CodingKeys: String, CodingKey {
        case persistentID = "persistent_id"
        case albumGroupKey = "album_group_key"
        case title, artist, album
        case albumArtist = "album_artist"
        case genre, year
        case trackNo = "track_no"
        case trackCount = "track_count"
        case discNo = "disc_no"
        case discCount = "disc_count"
        case artworkRef = "artwork_ref"
        case artworkCandidates = "artwork_candidates_json"
        case source
        case externalReleaseID = "external_release_id"
        case externalRecordingID = "external_recording_id"
        case isrc
        case fieldStatus = "field_status_json"
        case evidence = "evidence_json"
        case confidenceScore = "confidence_score"
        case confidenceLevel = "confidence_level"
        case blocksAutoApply = "blocks_auto_apply"
        case decision
        case finalValuesJSON = "final_values_json"
        case trackModifiedAt = "track_modified_at"
        case identifiedAt = "identified_at"
        case missingAtIdentification = "missing_fields_json"
    }

    public func status(of field: ProposalField) -> FieldStatus {
        fieldStatus[field.rawValue] ?? .noMatch
    }
}

/// 검토 화면에서 보여 줄 판단 근거
public struct ProposalEvidence: Codable, Sendable, Equatable {
    public var match: MatchEvidence?
    public var reasons: [String]
    public var error: String?
}

/// 앨범 단위 식별 결과
public struct AlbumResolvedRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "albums_resolved"

    public var albumGroupKey: String
    public var source: ProviderID
    public var externalReleaseID: String
    public var title: String
    public var albumArtist: String?
    public var year: Int?
    public var genre: String?
    public var trackCount: Int?
    public var discCount: Int?
    public var artworkURL: String?
    public var artworkWidth: Int?
    public var confidenceScore: Int
    public var confidenceLevel: ConfidenceLevel
    public var alternatives: [ReleaseCandidate]
    public var resolvedAt: Date

    enum CodingKeys: String, CodingKey {
        case albumGroupKey = "album_group_key"
        case source
        case externalReleaseID = "external_release_id"
        case title
        case albumArtist = "album_artist"
        case year, genre
        case trackCount = "track_count"
        case discCount = "disc_count"
        case artworkURL = "artwork_url"
        case artworkWidth = "artwork_width"
        case confidenceScore = "confidence_score"
        case confidenceLevel = "confidence_level"
        case alternatives = "alternatives_json"
        case resolvedAt = "resolved_at"
    }
}

extension ProviderID: DatabaseValueConvertible {}
extension ConfidenceLevel: DatabaseValueConvertible {}
extension ProposalDecision: DatabaseValueConvertible {}

extension AppDatabase {
    struct ProposalState {
        let trackModifiedAt: Double?
        let level: ConfidenceLevel
        let decision: ProposalDecision
        let missing: [RequiredField]
    }

    func proposalStates() throws -> [PersistentID: ProposalState] {
        try writer.read { db in
            var result: [PersistentID: ProposalState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT persistent_id, track_modified_at, confidence_level, decision, missing_fields_json FROM proposals") {
                guard let id = PersistentID(hex: row["persistent_id"]),
                      let level = ConfidenceLevel(rawValue: row["confidence_level"]),
                      let decision = ProposalDecision(rawValue: row["decision"]) else { continue }
                let missingJSON: String = row["missing_fields_json"] ?? "[]"
                let missing = (try? JSONDecoder().decode([RequiredField].self, from: Data(missingJSON.utf8))) ?? []
                result[id] = ProposalState(trackModifiedAt: row["track_modified_at"], level: level, decision: decision, missing: missing)
            }
            return result
        }
    }

    /// 곡별 마지막 적용 시도 (되돌리기 작업 제외)
    public func latestApplyAttempts() throws -> [String: ApplyResultRecord] {
        try writer.read { db in
            let rows = try ApplyResultRecord.fetchAll(db, sql: """
                SELECT r.* FROM apply_results r JOIN jobs j ON j.id = r.job_id
                WHERE j.kind != 'UNDO' ORDER BY r.job_id
                """)
            var latest: [String: ApplyResultRecord] = [:]
            for row in rows { latest[row.persistentID] = row }
            return latest
        }
    }

    public func proposals() throws -> [ProposalRecord] {
        try writer.read { db in try ProposalRecord.fetchAll(db) }
    }

    public func resolvedAlbums() throws -> [AlbumResolvedRecord] {
        try writer.read { db in try AlbumResolvedRecord.fetchAll(db) }
    }

    func saveIdentification(album: AlbumResolvedRecord?, albumGroupKey: String, proposals: [ProposalRecord]) throws {
        try writer.write { db in
            if let album {
                try album.upsert(db)
            } else {
                _ = try AlbumResolvedRecord.deleteOne(db, key: albumGroupKey)
            }
            for var proposal in proposals {
                if let existing = try ProposalRecord.fetchOne(db, key: proposal.persistentID) {
                    // 사용자가 직접 입력한 값은 다시 식별해도 덮어쓰지 않는다
                    if existing.decision == .userOverride { continue }
                    // 거절 결정은 유지한다
                    if existing.decision == .rejected { proposal.decision = .rejected }
                }
                try proposal.upsert(db)
            }
        }
    }

    /// 입력한 정보로 다시 식별한 결과로 바꾼다 (직접 수정·거절 결정도 새 식별 결과로 대체 = 검토 대기)
    public func saveHintedIdentification(_ proposal: ProposalRecord) throws {
        try writer.write { db in try proposal.upsert(db) }
    }

    /// 식별을 다시 실행하는 시점 기준으로 상태를 초기화한다.
    /// - 더 이상 정리 대상이 아닌 곡(완비됨·범위 밖)의 제안은 결정과 관계없이 지운다 (적용 기록은 작업 이력에 남음)
    /// - 직접 수정을 뺀 모든 결정(승인·거절·채울 값 없음)을 검토 대기로 되돌린다 (사용자 요청: 되돌린 곡도 다시 적용 가능하게)
    public func pruneProposals(keeping eligible: Set<String>) throws {
        try writer.write { db in
            let rows = try String.fetchAll(db, sql: "SELECT persistent_id FROM proposals")
            let stale = rows.filter { !eligible.contains($0) }
            if !stale.isEmpty { try ProposalRecord.deleteAll(db, keys: stale) }
            // 식별을 다시 실행한 시점부터 상태를 새로 센다 (이전 적용 결과·거절은 상태에 반영하지 않음).
            // 직접 수정(USER_OVERRIDE)은 결정도, 식별 시각도 보존해야 이미 적용한 직접수정 곡이
            // 다시 식별해도 '적용 완료'로 유지되고 검토함·전체 적용에 다시 끼어들지 않는다.
            try db.execute(sql: "UPDATE proposals SET decision = 'PENDING' WHERE decision != 'USER_OVERRIDE'")
            try db.execute(sql: "UPDATE proposals SET identified_at = ? WHERE decision != 'USER_OVERRIDE'", arguments: [Date()])
            try db.execute(sql: "DELETE FROM albums_resolved WHERE album_group_key NOT IN (SELECT DISTINCT album_group_key FROM proposals)")
        }
    }

    /// 사용자가 직접 입력한 값으로 제안을 바꾼다 (식별 실패한 곡도 가능). 빈 문자열·0은 '입력 안 함'
    /// 사용자가 끌어 놓은 이미지를 커버 1순위 후보로 지정 (다른 제안값·결정은 그대로)
    public func setArtworkFile(_ file: URL, for ids: [PersistentID]) throws {
        try writer.write { db in
            for id in ids {
                guard var record = try ProposalRecord.fetchOne(db, key: id.hex) else { continue }
                let candidate = "file:\(file.path)"
                record.artworkCandidates = [candidate] + record.artworkCandidates.filter { !$0.hasPrefix("file:") }
                record.artworkRef = candidate
                try record.update(db)
            }
        }
    }

    /// 검토 대기함에서 거절 (Music에는 쓰지 않음)
    public func reject(_ ids: [PersistentID]) throws {
        try writer.write { db in
            for id in ids {
                try db.execute(sql: "UPDATE proposals SET decision = 'REJECTED' WHERE persistent_id = ?", arguments: [id.hex])
            }
        }
    }

    public func saveOverride(persistentID: PersistentID, albumGroupKey: String, values: [ProposalField: FieldValue],
                             artworkFile: URL?, keepArtworkCandidates: Bool) throws {
        try writer.write { db in
            var record = try ProposalRecord.fetchOne(db, key: persistentID.hex) ?? ProposalRecord(
                persistentID: persistentID.hex, albumGroupKey: albumGroupKey, fieldStatus: [:],
                evidence: ProposalEvidence(match: nil, reasons: [], error: nil), confidenceScore: 0,
                confidenceLevel: .none, blocksAutoApply: true, decision: .pending, identifiedAt: Date())
            func text(_ field: ProposalField) -> String? {
                if case .text(let value)? = values[field], !Normalizer.clean(value).isEmpty { return Normalizer.clean(value) }
                return nil
            }
            func number(_ field: ProposalField) -> Int? {
                if case .number(let value)? = values[field], value > 0 { return value }
                return nil
            }
            record.title = text(.title)
            record.artist = text(.artist)
            record.album = text(.album)
            record.albumArtist = text(.albumArtist)
            record.genre = text(.genre)
            record.year = number(.year)
            record.trackNo = number(.trackNumber)
            record.trackCount = number(.trackCount)
            record.discNo = number(.discNumber)
            record.discCount = number(.discCount)
            if let artworkFile {
                record.artworkCandidates = ["file:\(artworkFile.path)"]
            } else if !keepArtworkCandidates {
                record.artworkCandidates = []
            }
            record.artworkRef = record.artworkCandidates.first
            record.decision = .userOverride
            record.blocksAutoApply = true
            record.identifiedAt = Date()  // 입력한 시점부터 상태를 새로 센다
            try record.upsert(db)
        }
    }
}
