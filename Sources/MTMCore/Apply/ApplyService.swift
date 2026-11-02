import Foundation
import GRDB

public struct ApplyProgress: Sendable {
    public var done: Int
    public var total: Int
    public var label: String
}

public struct JobSummary: Sendable, Equatable {
    public var jobID: Int64
    public var total = 0
    public var verified = 0
    public var verifyFailed = 0
    public var failed = 0
    public var skipped = 0
    /// 아직 처리하지 못한 항목이 남음 (중단됨)
    public var unfinished = 0
}

public enum UndoScope: Sendable, Equatable {
    case job(Int64)
    case album(jobID: Int64, albumGroupKey: String?)
    case track(jobID: Int64, PersistentID)

    var jobID: Int64 {
        switch self {
        case .job(let id), .album(let id, _), .track(let id, _): return id
        }
    }
}

/// 변경 전 상태 저장. 스냅샷 기록과 '쓰는 중' 표시를 한 트랜잭션으로 남긴다.
final class SnapshotService: Sendable {
    private let database: AppDatabase
    private let music: MusicScripting
    private let backupDirectory: URL
    private let fullFileBackup: Bool

    init(database: AppDatabase, music: MusicScripting, backupDirectory: URL, fullFileBackup: Bool = false) {
        self.database = database
        self.music = music
        self.backupDirectory = backupDirectory
        self.fullFileBackup = fullFileBackup
    }

    /// 원본 음악 파일 복사 (APFS에서는 복제라 바뀐 부분만큼만 용량을 쓴다)
    private func backupFile(_ location: String?, jobID: Int64, id: PersistentID) throws -> String? {
        guard fullFileBackup, let location, FileManager.default.fileExists(atPath: location) else { return nil }
        let directory = backupDirectory.appendingPathComponent("Files/job\(jobID)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: location)
        let target = directory.appendingPathComponent("\(id.hex) \(source.lastPathComponent)")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        return target.path
    }

    func capture(jobID: Int64, id: PersistentID, current: TrackFields, change: TrackChange) async throws -> Snapshot {
        var artworkPath: String?
        // 기존 커버를 교체하는 경우(고급 정책)에만 원본 커버를 파일로 백업
        if case .set = change.artwork, current.artworkCount > 0 {
            guard let data = try await music.artworkData(of: id) else { throw ArtworkError.unavailable }
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let file = backupDirectory.appendingPathComponent("job\(jobID)-\(id.hex).artwork")
            try data.write(to: file, options: .atomic)
            artworkPath = file.path
        }
        let changeJSON = String(data: try JSONEncoder().encode(change), encoding: .utf8)
        let backupPath = artworkPath
        let fileBackup = try backupFile(current.location, jobID: jobID, id: id)
        try await database.writer.write { db in
            var record = SnapshotRecord(id: nil, jobID: jobID, persistentID: id.hex, before: current,
                                        beforeArtworkPath: backupPath, createdAt: Date(), beforeFilePath: fileBackup)
            try record.insert(db)
            try db.execute(sql: """
                UPDATE apply_results SET state = 'WRITING', change_json = ?, updated_at = ?
                WHERE job_id = ? AND persistent_id = ?
                """, arguments: [changeJSON, Date(), jobID, id.hex])
        }
        return Snapshot(jobID: jobID, persistentID: id, before: current, beforeArtworkPath: artworkPath)
    }

    func load(jobID: Int64, id: PersistentID) throws -> Snapshot? {
        try database.writer.read { db in
            try SnapshotRecord.filter(Column("job_id") == jobID && Column("persistent_id") == id.hex).fetchOne(db)
        }.map { Snapshot(jobID: $0.jobID, persistentID: id, before: $0.before, beforeArtworkPath: $0.beforeArtworkPath) }
    }
}

/// 승인된 제안을 작업(Job)으로 만들어 스냅샷 → 쓰기 → 검증 순서로 적용하고, 되돌리기도 같은 방식으로 처리한다.
/// 곡 하나가 실패해도 작업은 계속한다. 앱이 중간에 꺼지면 같은 작업을 다시 실행해 이어서 진행한다.
public final class ApplyService: Sendable {
    private let database: AppDatabase
    private let music: MusicScripting
    private let writer: LibraryWriter
    private let artwork: ArtworkService
    private let snapshots: SnapshotService
    private let rules: CompletenessRules
    private let policies: WritePolicies

    /// - Parameter fullFileBackup: 쓰기 전에 원본 음악 파일을 통째로 백업 (기본 꺼짐: 메타데이터 스냅샷으로 충분)
    public init(database: AppDatabase, music: MusicScripting, writer: LibraryWriter, artwork: ArtworkService,
                backupDirectory: URL, rules: CompletenessRules, policies: WritePolicies, fullFileBackup: Bool = false) {
        self.database = database
        self.music = music
        self.writer = writer
        self.artwork = artwork
        self.rules = rules
        self.policies = policies
        snapshots = SnapshotService(database: database, music: music, backupDirectory: backupDirectory, fullFileBackup: fullFileBackup)
    }

    // MARK: - 작업 만들기

    /// 제안을 작업으로 기록한다 (아직 Music에는 쓰지 않음). 같은 곡이 다른 열린 작업에 있으면 건너뛴다.
    public func createJob(kind: JobKind, proposals: [ProposalRecord], tracks: [PersistentID: LibraryTrack]) async throws -> Int64? {
        let decision: ProposalDecision = kind == .auto ? .autoApproved : .userApproved
        // §8 '검사 이후 변경' 가드의 기준값을 적용 때와 같은 출처(Music 스크립팅)로 맞춘다.
        // ITLibrary 스캔값과 스크립팅 값이 달라 생기던 오탐(멀쩡한 곡이 '직접 수정됨'으로 건너뜀)을 없앤다.
        let ids = proposals.compactMap { PersistentID(hex: $0.persistentID) }
        let scriptingFields = (try? await music.readTracks(ids)) ?? [:]
        return try await database.writer.write { db in
            let busy = Set(try String.fetchAll(db, sql: "SELECT persistent_id FROM apply_results WHERE state IN ('PLANNED', 'WRITING')"))
            var job = JobRecord(id: nil, kind: kind, startedAt: Date(), total: 0, applied: 0, failed: 0, skipped: 0)
            try job.insert(db)
            guard let jobID = job.id else { return nil }
            var count = 0
            for proposal in proposals where !busy.contains(proposal.persistentID) {
                guard let id = PersistentID(hex: proposal.persistentID), let track = tracks[id] else { continue }
                // 사용자가 직접 입력한 값은 그대로 쓰고, 결정도 '직접 수정'으로 유지
                let isOverride = proposal.decision == .userOverride
                // 기준값: 스크립팅으로 읽은 값이 있으면 그걸 쓰고(적용 때와 같은 출처), 없으면 ITLibrary 스캔값으로
                let scanned = scriptingFields[id].map(ScannedValues.init) ?? ScannedValues(track)
                let plan: ApplyPlan = isOverride
                    ? .override(values: proposal.proposedValues, artworkCandidates: proposal.artworkCandidates, scanned: scanned)
                    : .apply(proposed: proposal.applicableValues(current: track), artworkCandidates: proposal.artworkCandidates,
                             scanned: scanned)
                try ApplyResultRecord(jobID: jobID, persistentID: id.hex, albumGroupKey: proposal.albumGroupKey,
                                      label: Self.label(track), state: .planned, plan: plan, updatedAt: Date()).insert(db)
                if !isOverride {
                    try db.execute(sql: "UPDATE proposals SET decision = ? WHERE persistent_id = ?", arguments: [decision, id.hex])
                }
                count += 1
            }
            guard count > 0 else {
                try job.delete(db)
                return nil
            }
            job.total = count
            try job.update(db)
            return jobID
        }
    }

    /// 되돌리기 작업 (곡·앨범·작업 단위). 되돌릴 것이 없으면 nil
    public func createUndoJob(_ scope: UndoScope) throws -> Int64? {
        try database.writer.write { db in
            var request = ApplyResultRecord.filter(Column("job_id") == scope.jobID && Column("undone_by_job_id") == nil)
                .filter([ApplyState.verified.rawValue, ApplyState.verifyFailed.rawValue].contains(Column("state")))
            switch scope {
            case .job: break
            case .album(_, let key): request = request.filter(Column("album_group_key") == key)
            case .track(_, let id): request = request.filter(Column("persistent_id") == id.hex)
            }
            let sources = try request.fetchAll(db)
            guard !sources.isEmpty,
                  try JobRecord.fetchOne(db, key: scope.jobID)?.kind != .undo else { return nil }
            var job = JobRecord(id: nil, kind: .undo, startedAt: Date(), total: sources.count, applied: 0, failed: 0,
                                skipped: 0, undoOfJobID: scope.jobID)
            try job.insert(db)
            guard let jobID = job.id else { return nil }
            for source in sources {
                try ApplyResultRecord(jobID: jobID, persistentID: source.persistentID, albumGroupKey: source.albumGroupKey,
                                      label: source.label, state: .planned, plan: .undo(sourceJobID: scope.jobID),
                                      updatedAt: Date()).insert(db)
            }
            return jobID
        }
    }

    /// 아직 시작하지 않은 항목을 취소하고 작업을 끝낸다. 이미 쓴 곡은 그대로 두며 되돌리기로 복원할 수 있다.
    /// '쓰는 중'인 곡은 스냅샷이 있으므로 먼저 마저 처리해야 한다 (이어서 실행 후 취소).
    @discardableResult
    public func cancel(jobID: Int64) throws -> JobSummary {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE apply_results SET state = 'CANCELLED', updated_at = ? WHERE job_id = ? AND state = 'PLANNED'
                """, arguments: [Date(), jobID])
            // 취소된 제안은 다시 검토 대기로
            try db.execute(sql: """
                UPDATE proposals SET decision = 'PENDING' WHERE persistent_id IN
                (SELECT persistent_id FROM apply_results WHERE job_id = ? AND state = 'CANCELLED')
                """, arguments: [jobID])
        }
        return try finish(jobID: jobID)
    }

    // MARK: - 실행

    /// 남은 항목을 처리한다. 중단된 작업도 같은 방법으로 이어서 실행한다.
    /// 안전장치·권한 없음·오프라인이면 작업을 멈추고 오류를 던진다 (남은 항목은 그대로 유지).
    @discardableResult
    public func run(jobID: Int64, progress: @escaping @Sendable (ApplyProgress) -> Void = { _ in }) async throws -> JobSummary {
        let all = try database.applyResults(jobID: jobID)
        let open = all.filter { $0.state.isOpen }
        var done = all.count - open.count
        for item in open {
            // 일시정지: 남은 곡은 '대기'로 두고 멈춘다 (다음에 이어서 실행)
            if Task.isCancelled { break }
            progress(ApplyProgress(done: done, total: all.count, label: item.label))
            let outcome: (state: ApplyState, message: String?)
            do {
                outcome = try await process(item, jobID: jobID)
            } catch let error as WriteError {
                throw error
            } catch let error as HTTPError where error == .offline {
                throw error
            } catch let error as MusicScriptError where error.number == -1743 {
                throw error
            } catch {
                Log.apply.error("적용 실패 \(item.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
                outcome = (.failed, error.localizedDescription)
            }
            try await database.writer.write { db in
                try db.execute(sql: """
                    UPDATE apply_results SET state = ?, error_message = ?, updated_at = ? WHERE job_id = ? AND persistent_id = ?
                    """, arguments: [outcome.state, outcome.message, Date(), jobID, item.persistentID])
            }
            done += 1
            progress(ApplyProgress(done: done, total: all.count, label: item.label))
        }
        return try finish(jobID: jobID)
    }

    private func process(_ item: ApplyResultRecord, jobID: Int64) async throws -> (state: ApplyState, message: String?) {
        guard let id = item.id else { return (.failed, MTMLoc.t("apply.err.badID", "잘못된 곡 ID")) }

        // 강제 종료로 '쓰는 중'에 멈춘 곡: 기록해 둔 같은 변경을 다시 적용 (같은 값을 다시 쓰므로 안전)
        if item.state == .writing, let change = item.change {
            guard let snapshot = try snapshots.load(jobID: jobID, id: id) else { return (.failed, MTMLoc.t("apply.err.noSnapshot", "스냅샷 없음")) }
            try await writer.apply(change, snapshot: snapshot)
            let result = try await verify(id, change: change, before: snapshot.before)
            try afterWrite(item, jobID: jobID, state: result.state)
            return result
        }

        guard let current = try await music.readTracks([id])[id] else {
            return (.failed, MTMLoc.t("apply.err.notFound", "Music 보관함에서 곡을 찾을 수 없습니다"))
        }
        try? database.recordArtworkTruth([id: current.artworkCount > 0])
        let change: TrackChange
        var artworkNote: String?
        switch item.plan {
        case .apply(let proposed, let candidates, let scanned), .override(let proposed, let candidates, let scanned):
            let isOverride: Bool
            if case .override = item.plan { isOverride = true } else { isOverride = false }
            // 직접 수정(override)은 사용자가 '직접 수정' 화면에서 명시적으로 확인·입력한 값이므로, '검사 이후 변경' 가드를
            // 적용하지 않고 그대로 쓴다. 자동/식별 적용(.apply)만 외부 편집 보호를 위해 가드를 둔다.
            if !isOverride {
                let changed = scanned.conflicts(with: current, proposed: proposed)
                if !changed.isEmpty {
                    try setDecision(.pending, for: id)
                    return (.skippedChanged, MTMLoc.f("apply.skip.changed", "검사 이후 Music에서 ‘%@’ 값이 사용자가 직접 바꾼 것으로 보여 적용하지 않았습니다. ‘직접 수정’에서 값을 확인해 적용하세요.", changed.joined(separator: ", ")))
                }
            }
            var (planned, wantsArtwork) = ChangePlanner.plan(proposed: proposed, hasArtworkCandidates: !candidates.isEmpty,
                                                             current: current, id: id, rules: rules,
                                                             policies: isOverride ? .userOverride : policies,
                                                             caseSensitive: isOverride)
            if wantsArtwork {
                let preparation = await artwork.prepareWithReport(candidates)
                if let prepared = preparation.prepared {
                    planned.artwork = .set(path: prepared.file.path, source: prepared.source)
                    if prepared.width < 600 { artworkNote = MTMLoc.f("apply.note.lowResUsed", "저해상도 커버 사용 (%d×%d)", prepared.width, prepared.height) }
                } else {
                    artworkNote = MTMLoc.f("apply.note.coverSkipped", "커버 미적용 — %@", preparation.failures.isEmpty ? MTMLoc.t("reason.noCandidate", "후보 없음") : preparation.failureSummary)
                }
            }
            if planned.isEmpty { return (.skippedNothing, artworkNote) }
            change = planned

        case .undo(let sourceJobID):
            guard let source = try await database.writer.read({ db in
                      try ApplyResultRecord.fetchOne(db, key: ["job_id": sourceJobID, "persistent_id": id.hex])
                  }),
                  source.state.wrote, source.undoneByJobID == nil, let applied = source.change,
                  let original = try snapshots.load(jobID: sourceJobID, id: id)
            else { return (.skippedNothing, MTMLoc.t("apply.undo.nothing", "되돌릴 변경이 없습니다")) }
            // 필드마다: 지금 값이 적용한 값이면 원래 값으로 복원, 이미 원래 값이면 그대로(예: Music이 쓰기를 무시한 필드),
            // 둘 다 아니면 적용 이후 사용자가 직접 고친 것이므로 이 곡은 되돌리지 않는다.
            var restore = TrackChange()
            for field in applied.fields where field != .artwork {
                guard let appliedValue = applied.value(of: field), let beforeValue = original.before.value(of: field) else { continue }
                let now = current.value(of: field)
                if Self.same(now, appliedValue) {
                    restore.values[field.rawValue] = beforeValue
                } else if !Self.same(now, beforeValue) {
                    return (.skippedChanged, MTMLoc.f("apply.undo.fieldEdited", "적용 이후 %@이(가) 직접 수정되어 되돌리지 않았습니다", field.label))
                }
            }
            if applied.artwork != nil {
                if current.artworkCount > 0 {
                    restore.artwork = original.beforeArtworkPath.map { .restore(path: $0) } ?? .delete
                } else if original.before.artworkCount > 0 {
                    return (.skippedChanged, MTMLoc.t("apply.undo.coverDeleted", "적용 이후 커버가 직접 삭제되어 되돌리지 않았습니다"))
                }
            }
            if restore.isEmpty { return (.skippedNothing, MTMLoc.t("apply.undo.alreadyOriginal", "이미 원래 값입니다")) }
            change = restore
        }

        let snapshot = try await snapshots.capture(jobID: jobID, id: id, current: current, change: change)
        try await writer.apply(change, snapshot: snapshot)
        let result = try await verify(id, change: change, before: current)
        try afterWrite(item, jobID: jobID, state: result.state)
        // 다른 필드는 썼지만 커버를 못 넣은 경우 이유를 남긴다
        let message = [result.message, artworkNote].compactMap { $0 }.joined(separator: " · ")
        return (result.state, message.isEmpty ? nil : message)
    }

    /// 다시 읽어 최종값과 비교한다. 파일 위치가 바뀌었으면(미디어 폴더 정리) 기록도 갱신한다.
    private func verify(_ id: PersistentID, change: TrackChange, before: TrackFields) async throws -> (state: ApplyState, message: String?) {
        guard let after = try await music.readTracks([id])[id] else {
            return (.verifyFailed, MTMLoc.t("apply.verify.rereadFail", "적용 후 곡을 다시 읽을 수 없습니다"))
        }
        var mismatches: [String] = []
        for field in change.fields where field != .artwork {
            if let expected = change.value(of: field), !Self.verifyMatches(after.value(of: field), expected, field: field) {
                mismatches.append(field.label)
            }
        }
        switch change.artwork {
        case .set, .restore: if after.artworkCount < 1 { mismatches.append(ProposalField.artwork.label) }
        case .delete: if after.artworkCount >= before.artworkCount { mismatches.append(ProposalField.artwork.label) }
        case nil: break
        }
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE tracks SET file_path = ? WHERE persistent_id = ?", arguments: [after.location, id.hex])
        }
        try? database.recordArtworkTruth([id: after.artworkCount > 0])
        return mismatches.isEmpty ? (.verified, nil) : (.verifyFailed, MTMLoc.f("apply.verify.mismatch", "다시 읽은 값이 다릅니다: %@", mismatches.joined(separator: ", ")))
    }

    private func afterWrite(_ item: ApplyResultRecord, jobID: Int64, state: ApplyState) throws {
        guard state.wrote, case .undo(let sourceJobID) = item.plan else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE apply_results SET undone_by_job_id = ? WHERE job_id = ? AND persistent_id = ?",
                           arguments: [jobID, sourceJobID, item.persistentID])
            // 되돌린 제안은 다시 자동 적용되지 않게 거절로 둔다
            try db.execute(sql: "UPDATE proposals SET decision = 'REJECTED' WHERE persistent_id = ?", arguments: [item.persistentID])
        }
    }

    private func setDecision(_ decision: ProposalDecision, for id: PersistentID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE proposals SET decision = ? WHERE persistent_id = ?", arguments: [decision, id.hex])
        }
    }

    private func finish(jobID: Int64) throws -> JobSummary {
        try database.writer.write { db in
            let results = try ApplyResultRecord.filter(Column("job_id") == jobID).fetchAll(db)
            var summary = JobSummary(jobID: jobID, total: results.count)
            for result in results {
                switch result.state {
                case .verified: summary.verified += 1
                case .verifyFailed: summary.verifyFailed += 1
                case .failed: summary.failed += 1
                case .skippedChanged, .skippedNothing, .cancelled: summary.skipped += 1
                case .planned, .writing: summary.unfinished += 1
                }
            }
            guard var job = try JobRecord.fetchOne(db, key: jobID) else { return summary }
            job.applied = summary.verified + summary.verifyFailed
            job.failed = summary.failed + summary.verifyFailed
            job.skipped = summary.skipped
            if summary.unfinished == 0 { job.finishedAt = Date() }
            try job.update(db)
            return summary
        }
    }

    /// 적용 후 검증 비교. 장르는 Music이 자체 장르 목록 기준으로 표기(주로 대소문자)를 바꿔 저장하므로
    /// (예: `pop` → `Pop`), 대소문자·연속 공백을 무시하고(compareKey) 비교해 오탐('검증 실패: 장르')을 막는다.
    /// 그 외 필드는 Music이 입력값을 그대로 저장하므로 정확 비교(same)를 유지한다.
    static func verifyMatches(_ after: FieldValue?, _ expected: FieldValue, field: ProposalField) -> Bool {
        if field == .genre, case .text(let a)? = after, case .text(let b) = expected {
            return Normalizer.compareKey(a) == Normalizer.compareKey(b)
        }
        return same(after, expected)
    }

    static func same(_ current: FieldValue?, _ expected: FieldValue) -> Bool {
        switch (current, expected) {
        case (.text(let a)?, .text(let b)): return Normalizer.clean(a) == Normalizer.clean(b)
        case (.number(let a)?, .number(let b)): return a == b
        default: return false
        }
    }

    static func label(_ track: LibraryTrack) -> String {
        let title = Normalizer.clean(track.title)
        let artist = Normalizer.clean(track.artist)
        return artist.isEmpty ? title : "\(title) — \(artist)"
    }
}
