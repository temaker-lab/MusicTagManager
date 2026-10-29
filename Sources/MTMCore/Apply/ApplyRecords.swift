import Foundation
import GRDB

public enum JobKind: String, Codable, Sendable {
    case auto = "AUTO", manual = "MANUAL", undo = "UNDO"
}

public enum ApplyState: String, Codable, Sendable {
    /// 계획만 됨 (아직 아무것도 안 씀)
    case planned = "PLANNED"
    /// 스냅샷 저장 후 쓰는 중 (강제 종료 시 같은 변경을 다시 적용)
    case writing = "WRITING"
    case verified = "VERIFIED"
    case verifyFailed = "VERIFY_FAILED"
    case failed = "FAILED"
    /// 스캔 이후 사용자가 Music에서 직접 고쳐 적용하지 않음
    case skippedChanged = "SKIPPED_CHANGED"
    /// 정책상 쓸 값이 없음
    case skippedNothing = "SKIPPED_NOTHING"
    /// 사용자가 작업을 취소해 처리하지 않음
    case cancelled = "CANCELLED"

    public var isOpen: Bool { self == .planned || self == .writing }
    /// 되돌릴 수 있는 상태 (실제로 쓴 곡)
    public var wrote: Bool { self == .verified || self == .verifyFailed }

    public var label: String {
        switch self {
        case .planned: return MTMLoc.t("applyState.planned", "대기")
        case .writing: return MTMLoc.t("applyState.writing", "쓰는 중")
        case .verified: return MTMLoc.t("applyState.verified", "완료")
        case .verifyFailed: return MTMLoc.t("applyState.verifyFailed", "검증 실패")
        case .failed: return MTMLoc.t("applyState.failed", "실패")
        case .skippedChanged: return MTMLoc.t("applyState.skippedChanged", "건너뜀 (직접 수정됨)")
        case .skippedNothing: return MTMLoc.t("applyState.skippedNothing", "건너뜀 (쓸 값 없음)")
        case .cancelled: return MTMLoc.t("applyState.cancelled", "취소됨")
        }
    }
}

public struct JobRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable, Equatable {
    public static let databaseTableName = "jobs"

    public var id: Int64?
    public var kind: JobKind
    public var startedAt: Date
    public var finishedAt: Date?
    public var total: Int
    public var applied: Int
    public var failed: Int
    public var skipped: Int
    public var undoOfJobID: Int64?
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case total, applied, failed, skipped
        case undoOfJobID = "undo_of_job_id"
        case note
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ApplyResultRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "apply_results"

    public var jobID: Int64
    public var persistentID: String
    public var albumGroupKey: String?
    /// 표시용 곡 이름 (작업 당시)
    public var label: String
    public var state: ApplyState
    public var plan: ApplyPlan
    /// 스냅샷과 함께 기록한 실제 변경 (재개·되돌리기 기준)
    public var change: TrackChange?
    public var errorMessage: String?
    public var undoneByJobID: Int64?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case persistentID = "persistent_id"
        case albumGroupKey = "album_group_key"
        case label, state
        case plan = "plan_json"
        case change = "change_json"
        case errorMessage = "error_message"
        case undoneByJobID = "undone_by_job_id"
        case updatedAt = "updated_at"
    }

    public var id: PersistentID? { PersistentID(hex: persistentID) }
}

public struct SnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "snapshots"

    public var id: Int64?
    public var jobID: Int64
    public var persistentID: String
    public var before: TrackFields
    public var beforeArtworkPath: String?
    public var createdAt: Date
    /// 원본 파일 전체 백업 (설정에서 켰을 때만)
    public var beforeFilePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case persistentID = "persistent_id"
        case before = "before_values_json"
        case beforeArtworkPath = "before_artwork_path"
        case createdAt = "created_at"
        case beforeFilePath = "before_file_path"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension JobKind: DatabaseValueConvertible {}
extension ApplyState: DatabaseValueConvertible {}

extension AppDatabase {
    static func registerApplyMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_apply") { db in
            try db.create(table: "jobs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("finished_at", .datetime)
                t.column("total", .integer).notNull().defaults(to: 0)
                t.column("applied", .integer).notNull().defaults(to: 0)
                t.column("failed", .integer).notNull().defaults(to: 0)
                t.column("skipped", .integer).notNull().defaults(to: 0)
                t.column("undo_of_job_id", .integer)
                t.column("note", .text)
            }
            try db.create(table: "apply_results") { t in
                t.column("job_id", .integer).notNull().references("jobs", onDelete: .cascade)
                t.column("persistent_id", .text).notNull()
                t.column("album_group_key", .text)
                t.column("label", .text).notNull()
                t.column("state", .text).notNull().indexed()
                t.column("plan_json", .text).notNull()
                t.column("change_json", .text)
                t.column("error_message", .text)
                t.column("undone_by_job_id", .integer)
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["job_id", "persistent_id"])
            }
            try db.create(table: "snapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs", onDelete: .cascade)
                t.column("persistent_id", .text).notNull()
                t.column("before_values_json", .text).notNull()
                t.column("before_artwork_path", .text)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["job_id", "persistent_id"])
            }
        }
    }

    public func jobs(limit: Int = 50) throws -> [JobRecord] {
        try writer.read { db in try JobRecord.order(Column("id").desc).limit(limit).fetchAll(db) }
    }

    public func applyResults(jobID: Int64) throws -> [ApplyResultRecord] {
        try writer.read { db in
            try ApplyResultRecord.filter(Column("job_id") == jobID)
                .order(Column("album_group_key"), Column("label")).fetchAll(db)
        }
    }

    /// 지금 Music에 적용된 상태로 남아 있는 곡 (되돌리지 않은 완료 항목)
    public func appliedTrackIDs() throws -> Set<String> {
        try writer.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT r.persistent_id FROM apply_results r JOIN jobs j ON j.id = r.job_id
                WHERE j.kind != 'UNDO' AND r.state IN ('VERIFIED', 'VERIFY_FAILED') AND r.undone_by_job_id IS NULL
                """))
        }
    }

    public func unfinishedJobIDs() throws -> [Int64] {
        try writer.read { db in
            try Int64.fetchAll(db, sql: "SELECT id FROM jobs WHERE finished_at IS NULL ORDER BY id")
        }
    }

    /// 아직 스냅샷(되돌리기 자료)이 남아 있는 작업 ID. 보존 기간이 지나 정리된 작업은 여기서 빠진다.
    public func jobIDsWithSnapshots() throws -> Set<Int64> {
        try writer.read { db in Set(try Int64.fetchAll(db, sql: "SELECT DISTINCT job_id FROM snapshots")) }
    }

    /// 보존 기간이 지난 스냅샷을 정리한다. 삭제한 행이 가리키던 백업 파일 경로를 돌려준다(호출부에서 파일 삭제).
    /// 아직 끝나지 않은(쓰는 중) 작업의 스냅샷은 재개에 필요하므로 건드리지 않는다.
    @discardableResult
    public func pruneSnapshots(olderThan cutoff: Date) throws -> [String] {
        try writer.write { db in
            let stale = try SnapshotRecord
                .filter(Column("created_at") < cutoff)
                .filter(sql: "job_id IN (SELECT id FROM jobs WHERE finished_at IS NOT NULL)")
                .fetchAll(db)
            guard !stale.isEmpty else { return [] }
            let paths = stale.flatMap { [$0.beforeArtworkPath, $0.beforeFilePath].compactMap { $0 } }
            let ids = stale.compactMap(\.id)
            try SnapshotRecord.filter(keys: ids).deleteAll(db)
            return paths
        }
    }
}
