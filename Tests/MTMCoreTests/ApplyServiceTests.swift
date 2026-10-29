import XCTest
import GRDB
@testable import MTMCore

final class ApplyServiceTests: XCTestCase {
    private var database: AppDatabase!
    private var music: FakeMusic!
    private var directory: URL!
    private let sibling = pid(9)

    /// 1: 가수·커버 없음, 2: 커버 없음, 3: 앨범·커버 없음, 9: 같은 앨범의 완비 곡(커버 있음)
    private func original(_ id: PersistentID) -> TrackFields {
        var fields = TrackFields()
        switch id {
        case pid(1): fields.title = "가을 아침"; fields.album = "꽃갈피 둘"
        case pid(2): fields.title = "비밀의 화원"; fields.artist = "아이유"; fields.album = "꽃갈피 둘"
        case pid(3): fields.title = "Africa"; fields.artist = "Toto"
        default: fields.title = "매일 그대와"; fields.artist = "아이유"; fields.album = "꽃갈피 둘"
        }
        fields.location = "/Music/old/\(fields.title).mp3"
        return fields
    }

    private func libraryTrack(_ id: PersistentID) -> LibraryTrack {
        original(id).libraryTrack(id: id)
    }

    override func setUp() async throws {
        database = try AppDatabase.inMemory()
        directory = temporaryDirectory()
        music = FakeMusic(Dictionary(uniqueKeysWithValues: [pid(1), pid(2), pid(3), sibling].map { ($0, original($0)) }))
        music.setArtworkData(sibling, [makeJPEG(width: 1000, height: 1000)])
        try database.saveIdentification(album: nil, albumGroupKey: "g", proposals: [pid(1), pid(2), pid(3)].map(proposal))
    }

    private func proposal(_ id: PersistentID) -> ProposalRecord {
        let isToto = id == pid(3)
        return ProposalRecord(
            persistentID: id.hex, albumGroupKey: isToto ? "single:\(id.hex)" : "아이유\u{1F}꽃갈피 둘",
            title: isToto ? "Africa" : original(id).title, artist: isToto ? "Toto" : "아이유",
            album: isToto ? "Toto IV" : "꽃갈피 둘", albumArtist: isToto ? "Toto" : "아이유", year: isToto ? 1982 : 2017,
            trackNo: isToto ? 10 : Int(id.rawValue), trackCount: 6, discNo: 1, discCount: 1,
            artworkRef: "track:\(sibling.hex)", artworkCandidates: isToto ? [] : ["track:\(sibling.hex)"],
            fieldStatus: [:], evidence: ProposalEvidence(match: nil, reasons: [], error: nil),
            confidenceScore: 90, confidenceLevel: .high, blocksAutoApply: false, decision: .pending, identifiedAt: Date())
    }

    private func makeService(maxTracks: Int? = 3_000, policies: WritePolicies = .fillEmptyOnly) -> ApplyService {
        ApplyService(database: database, music: music, writer: LibraryWriter(music: music, maxLibraryTracks: maxTracks, retryDelay: 0),
                     artwork: ArtworkService(directory: directory.appendingPathComponent("art"), music: music),
                     backupDirectory: directory.appendingPathComponent("backup"), rules: CompletenessRules(), policies: policies)
    }

    private func createJob(_ service: ApplyService, _ ids: [PersistentID] = [pid(1), pid(2), pid(3)]) async throws -> Int64 {
        let tracks = Dictionary(uniqueKeysWithValues: ids.map { ($0, libraryTrack($0)) })
        let jobID = try await service.createJob(kind: .manual, proposals: ids.map(proposal), tracks: tracks)
        return try XCTUnwrap(jobID)
    }

    private func result(_ jobID: Int64, _ id: PersistentID) throws -> ApplyResultRecord {
        try XCTUnwrap(try database.applyResults(jobID: jobID).first { $0.persistentID == id.hex })
    }

    private func decision(_ id: PersistentID) throws -> ProposalDecision? {
        try database.proposals().first { $0.persistentID == id.hex }?.decision
    }

    // MARK: - 적용

    func testAppliesOnlyEmptyFieldsAndVerifies() async throws {
        let service = makeService()
        let jobID = try await createJob(service)
        XCTAssertEqual(try decision(pid(1)), .userApproved)
        XCTAssertEqual(music.writeCount, 0, "작업을 만들기만 해서는 쓰지 않는다")

        let summary = try await service.run(jobID: jobID)
        XCTAssertEqual(summary.verified, 3)
        XCTAssertEqual(summary.unfinished, 0)

        let first = try XCTUnwrap(music.fields(pid(1)))
        XCTAssertEqual(first.artist, "아이유")
        XCTAssertEqual(first.title, "가을 아침")
        XCTAssertEqual(first.trackNumber, 1)
        XCTAssertEqual(first.artworkCount, 1)
        XCTAssertEqual(music.artworkList(pid(1)).first.flatMap(imageSize)?.0, 1000, "같은 앨범 곡의 커버")
        // 3번: 커버 후보가 없으니 텍스트만, 이미 있는 가수는 그대로
        let toto = try XCTUnwrap(music.fields(pid(3)))
        XCTAssertEqual(toto.album, "Toto IV")
        XCTAssertEqual(toto.artworkCount, 0)

        let job = try XCTUnwrap(try database.jobs().first)
        XCTAssertNotNil(job.finishedAt)
        XCTAssertEqual(job.applied, 3)
        // 파일이 옮겨졌으면 위치 기록을 갱신
        XCTAssertEqual(try result(jobID, pid(1)).state, .verified)
        XCTAssertEqual(try database.appliedTrackIDs(), Set([pid(1), pid(2), pid(3)].map(\.hex)))
    }

    func testSnapshotIsSavedBeforeEveryWrite() async throws {
        let service = makeService()
        let jobID = try await createJob(service)
        var missingSnapshot: [PersistentID] = []
        music.onWrite = { [database] id in
            let exists = (try? database!.writer.read { db in
                try SnapshotRecord.filter(Column("job_id") == jobID && Column("persistent_id") == id.hex).fetchCount(db)
            }) ?? 0
            if exists == 0 { missingSnapshot.append(id) }
        }
        try await service.run(jobID: jobID)
        XCTAssertGreaterThan(music.writeCount, 0)
        XCTAssertEqual(missingSnapshot, [])
    }

    func testSkipsTrackEditedByUserSinceScan() async throws {
        let service = makeService()
        let jobID = try await createJob(service, [pid(1)])
        music.edit(pid(1)) { $0.artist = "직접 입력한 가수" }
        let summary = try await service.run(jobID: jobID)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(try result(jobID, pid(1)).state, .skippedChanged)
        XCTAssertEqual(music.fields(pid(1))?.artist, "직접 입력한 가수")
        XCTAssertEqual(music.writeCount, 0)
        XCTAssertEqual(try decision(pid(1)), .pending, "검토 대기로 돌려놓는다")
    }

    /// 실측 140곡: 검사 때 커버가 있다고 했는데 Music에는 없음 → 건너뛰지 않고 커버를 채운다
    func testStaleArtworkFlagDoesNotBlockApply() async throws {
        let service = makeService()
        var track = libraryTrack(pid(1))
        track.hasArtwork = true
        let jobID = (try await service.createJob(kind: .manual, proposals: [proposal(pid(1))], tracks: [pid(1): track]))!
        try await service.run(jobID: jobID)
        XCTAssertEqual(try result(jobID, pid(1)).state, .verified)
        XCTAssertEqual(music.fields(pid(1))?.artworkCount, 1)
        XCTAssertEqual(try database.artworkTruth()[pid(1).hex]?.hasArtwork, true, "읽은 실제 값을 기록")
    }

    func testClearHistoryRemovesJobsAndProposals() async throws {
        let service = makeService()
        try await service.run(jobID: try await createJob(service))
        try database.clearHistory()
        XCTAssertEqual(try database.jobs(), [])
        XCTAssertEqual(try database.appliedTrackIDs(), [])
        XCTAssertEqual(try database.proposals(), [])
    }

    func testVerifyFailureIsRecorded() async throws {
        music.ignoredFields = [.artist]
        let service = makeService()
        let jobID = try await createJob(service, [pid(1)])
        try await service.run(jobID: jobID)
        let item = try result(jobID, pid(1))
        XCTAssertEqual(item.state, .verifyFailed)
        XCTAssertTrue(item.errorMessage?.contains("가수명") == true)
    }

    func testOneFailureDoesNotStopTheJob() async throws {
        music.failBefore = { op, id in op == .write && id == pid(2) ? MusicScriptError(number: -10000, message: "x") : nil }
        let service = makeService()
        let jobID = try await createJob(service)
        let summary = try await service.run(jobID: jobID)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.verified, 2)
        XCTAssertEqual(try result(jobID, pid(2)).state, .failed)
    }

    func testSafetyGuardBlocksLargeLibrary() async throws {
        music.libraryCount = 8_042
        let service = makeService(maxTracks: 3_000)
        let jobID = try await createJob(service)
        do {
            try await service.run(jobID: jobID)
            XCTFail("안전장치가 막아야 함")
        } catch {
            XCTAssertEqual(error as? WriteError, .guardBlocked(libraryTracks: 8_042, limit: 3_000))
        }
        XCTAssertEqual(music.writeCount, 0)
        XCTAssertEqual(try database.unfinishedJobIDs(), [jobID], "작업은 남아 있어 나중에 이어서 할 수 있다")
    }

    func testTrackAlreadyInOpenJobIsNotQueuedTwice() async throws {
        let service = makeService()
        _ = try await createJob(service, [pid(1), pid(2)])
        let second = try await service.createJob(kind: .manual, proposals: [proposal(pid(1))], tracks: [pid(1): libraryTrack(pid(1))])
        XCTAssertNil(second)
    }

    func testCancelLeavesWrittenTracksAndReturnsRestToReview() async throws {
        music.failAfter = { op, id in op == .write && id == pid(1) ? MusicScriptError(number: -1743, message: "stop") : nil }
        let service = makeService()
        let jobID = try await createJob(service)
        do { try await service.run(jobID: jobID) } catch {}
        music.failAfter = nil
        // '쓰는 중'인 곡은 취소 대상이 아니다 → 먼저 마저 처리
        XCTAssertEqual(try service.cancel(jobID: jobID).unfinished, 1)
        try await service.run(jobID: jobID)
        let summary = try service.cancel(jobID: jobID)
        XCTAssertEqual(summary.unfinished, 0)
        XCTAssertEqual(try result(jobID, pid(2)).state, .cancelled)
        XCTAssertEqual(try decision(pid(2)), .pending)
        XCTAssertEqual(try database.unfinishedJobIDs(), [])
        XCTAssertEqual(music.fields(pid(2))?.artworkCount, 0, "취소된 곡은 그대로")
    }

    // MARK: - 교체 정책과 안전장치

    func testReplacePolicyOverwritesExistingAlbum() async throws {
        let service = makeService(policies: WritePolicies())
        let jobID = try await createJob(service, [pid(3)])
        try await service.run(jobID: jobID)
        XCTAssertEqual(music.fields(pid(3))?.album, "Toto IV")
        music.edit(pid(3)) { _ in }
        // 기존 앨범명이 있어도 기본 정책(다르면 교체)이면 바뀐다
        var proposal = proposal(pid(2))
        proposal.album = "꽃갈피 둘 (리마스터)"
        try database.saveIdentification(album: nil, albumGroupKey: "g", proposals: [proposal])
        let second = (try await service.createJob(kind: .manual, proposals: [proposal], tracks: [pid(2): libraryTrack(pid(2))]))!
        try await service.run(jobID: second)
        XCTAssertEqual(music.fields(pid(2))?.album, "꽃갈피 둘 (리마스터)")
    }

    /// 사용자 결정: 적용을 고르면 식별 결과가 기존 값과 크게 달라도 교체한다 (정확성은 신뢰도로 판단)
    func testUserChosenApplyReplacesEvenMismatchedValues() async throws {
        var proposal = proposal(pid(2))
        proposal.title = "Kiss the Rain"
        var match = MatchEvidence()
        match.coreMismatch = true
        proposal.evidence = ProposalEvidence(match: match, reasons: [], error: nil)
        let service = makeService(policies: WritePolicies())
        let jobID = (try await service.createJob(kind: .manual, proposals: [proposal], tracks: [pid(2): libraryTrack(pid(2))]))!
        try await service.run(jobID: jobID)
        XCTAssertEqual(music.fields(pid(2))?.title, "Kiss the Rain")
        XCTAssertEqual(music.fields(pid(2))?.artworkCount, 1)
    }

    func testPreviewExplainsMissingArtworkCandidate() {
        var proposal = proposal(pid(2))
        proposal.artworkCandidates = []
        proposal.album = "Away From the Sun"
        var track = libraryTrack(pid(2))
        track.album = "When I'm Gone-CDS"
        let preview = proposal.preview(current: track, rules: CompletenessRules(), policies: .fillEmptyOnly)
        XCTAssertTrue(preview.fields.contains(.albumArtist))
        proposal.albumArtist = nil
        proposal.year = nil
        proposal.trackNo = nil
        proposal.trackCount = nil
        proposal.discNo = nil
        proposal.discCount = nil
        let empty = proposal.preview(current: track, rules: CompletenessRules(), policies: .fillEmptyOnly)
        XCTAssertEqual(empty.fields, [])
        XCTAssertEqual(empty.reason, "커버 후보 없음 — 식별된 앨범(Away From the Sun)이 로컬 앨범과 다름")
        // 기본 정책이면 앨범명이 교체 대상
        XCTAssertEqual(proposal.preview(current: track, rules: CompletenessRules(), policies: WritePolicies()).fields, [.album])
    }

    func testArtworkFailureIsReportedEvenWhenOtherFieldsWritten() async throws {
        var proposal = proposal(pid(1))
        proposal.artworkCandidates = ["track:\(pid(3).hex)"]  // 커버 없는 곡 → 후보 실패
        try database.saveIdentification(album: nil, albumGroupKey: "g", proposals: [proposal])
        let service = makeService()
        let jobID = (try await service.createJob(kind: .manual, proposals: [proposal], tracks: [pid(1): libraryTrack(pid(1))]))!
        try await service.run(jobID: jobID)
        let item = try result(jobID, pid(1))
        XCTAssertEqual(item.state, .verified)
        XCTAssertEqual(music.fields(pid(1))?.artist, "아이유")
        XCTAssertTrue(item.errorMessage?.hasPrefix("커버 미적용") == true, item.errorMessage ?? "nil")
    }

    // MARK: - 직접 수정

    func testUserOverrideReplacesExistingValuesAndUsesChosenFile() async throws {
        let file = directory.appendingPathComponent("mine.jpg")
        try makeJPEG(width: 500, height: 320).write(to: file)
        try database.saveOverride(persistentID: pid(2), albumGroupKey: "g",
                                  values: [.title: .text("내가 고친 제목"), .album: .text(""), .year: .number(2018)],
                                  artworkFile: file, keepArtworkCandidates: false)
        let saved = try XCTUnwrap(try database.proposals().first { $0.persistentID == pid(2).hex })
        XCTAssertEqual(saved.decision, .userOverride)
        XCTAssertNil(saved.album, "빈 칸은 바꾸지 않는다")

        let service = makeService()  // 전역 정책은 '비어 있을 때만'이어도
        let jobID = (try await service.createJob(kind: .manual, proposals: [saved], tracks: [pid(2): libraryTrack(pid(2))]))!
        try await service.run(jobID: jobID)
        let fields = try XCTUnwrap(music.fields(pid(2)))
        XCTAssertEqual(fields.title, "내가 고친 제목")
        XCTAssertEqual(fields.album, "꽃갈피 둘")
        XCTAssertEqual(fields.year, 2018)
        XCTAssertEqual(music.artworkList(pid(2)).first.flatMap(imageSize)?.0, 500)
        XCTAssertEqual(try decision(pid(2)), .userOverride)

        try await service.run(jobID: try XCTUnwrap(try service.createUndoJob(.job(jobID))))
        XCTAssertEqual(music.fields(pid(2))?.title, "비밀의 화원")
        XCTAssertEqual(music.fields(pid(2))?.artworkCount, 0)
    }

    func testCancelledRunLeavesRestForLater() async throws {
        let service = makeService()
        let jobID = try await createJob(service)
        let task = Task { () -> JobSummary in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.run(jobID: jobID)
        }
        let summary = try await task.value
        XCTAssertEqual(summary.unfinished, 3)
        XCTAssertEqual(music.writeCount, 0)
        XCTAssertEqual(try database.unfinishedJobIDs(), [jobID])
    }

    func testFullFileBackupCopiesOriginalBeforeWriting() async throws {
        let original = directory.appendingPathComponent("song.mp3")
        try Data("원본 오디오".utf8).write(to: original)
        music.edit(pid(1)) { $0.location = original.path }
        let service = ApplyService(database: database, music: music, writer: LibraryWriter(music: music, maxLibraryTracks: nil, retryDelay: 0),
                                   artwork: ArtworkService(directory: directory.appendingPathComponent("art"), music: music),
                                   backupDirectory: directory.appendingPathComponent("backup"), rules: CompletenessRules(),
                                   policies: .fillEmptyOnly, fullFileBackup: true)
        var track = libraryTrack(pid(1))
        track.fileURL = original
        let jobID = (try await service.createJob(kind: .manual, proposals: [proposal(pid(1))], tracks: [pid(1): track]))!
        try await service.run(jobID: jobID)
        let record: SnapshotRecord? = try await database.writer.read { db in try SnapshotRecord.fetchOne(db) }
        let snapshot = try XCTUnwrap(record)
        let backup = try XCTUnwrap(snapshot.beforeFilePath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: backup)), Data("원본 오디오".utf8))
        XCTAssertTrue(backup.contains("job\(jobID)"))
    }

    func testDroppedArtworkFileBecomesFirstCandidate() throws {
        let file = directory.appendingPathComponent("drop.jpg")
        try database.setArtworkFile(file, for: [pid(1), pid(2)])
        let proposals = try database.proposals()
        XCTAssertEqual(proposals.first { $0.persistentID == pid(1).hex }?.artworkCandidates.first, "file:\(file.path)")
        XCTAssertEqual(proposals.first { $0.persistentID == pid(1).hex }?.decision, .pending, "결정은 그대로")
    }

    // MARK: - 강제 종료 후 재개

    func testResumesAfterCrashMidWrite() async throws {
        // 2번 곡: 텍스트를 쓴 직후(상태 기록 전) 앱이 죽은 상황 → 권한 오류로 작업 중단을 흉내 낸다
        music.failAfter = { op, id in op == .write && id == pid(2) ? MusicScriptError(number: -1743, message: "crash") : nil }
        let jobID = try await createJob(makeService())
        do {
            try await makeService().run(jobID: jobID)
            XCTFail()
        } catch {}
        // 처리 순서: 앨범 그룹 키·곡 이름 순 → 3번(단독), 1번, 2번
        XCTAssertEqual(try result(jobID, pid(3)).state, .verified)
        XCTAssertEqual(try result(jobID, pid(1)).state, .verified)
        XCTAssertEqual(try result(jobID, pid(2)).state, .writing, "스냅샷 저장 후 쓰다가 멈춤")
        XCTAssertEqual(try database.unfinishedJobIDs(), [jobID])
        let snapshotBefore = try XCTUnwrap(try SnapshotService(database: database, music: music, backupDirectory: directory)
            .load(jobID: jobID, id: pid(2)))

        // 재실행: 같은 작업을 이어서
        music.failAfter = nil
        let summary = try await makeService().run(jobID: jobID)
        XCTAssertEqual(summary.verified, 3)
        XCTAssertEqual(summary.unfinished, 0)
        XCTAssertEqual(music.fields(pid(2))?.artworkCount, 1)
        XCTAssertEqual(music.fields(pid(2))?.trackNumber, 2)
        // 스냅샷은 처음 것 그대로 (쓰기 도중 값으로 덮어쓰지 않음)
        let snapshotAfter = try XCTUnwrap(try SnapshotService(database: database, music: music, backupDirectory: directory)
            .load(jobID: jobID, id: pid(2)))
        XCTAssertEqual(snapshotAfter.before, snapshotBefore.before)
        XCTAssertEqual(snapshotAfter.before.trackNumber, 0)
        XCTAssertEqual(try database.unfinishedJobIDs(), [])
    }

    // MARK: - 되돌리기

    func testUndoWholeJobRestoresOriginalValues() async throws {
        let service = makeService()
        let jobID = try await createJob(service)
        try await service.run(jobID: jobID)

        let undoID = try XCTUnwrap(try service.createUndoJob(.job(jobID)))
        let summary = try await service.run(jobID: undoID)
        XCTAssertEqual(summary.verified, 3)
        for id in [pid(1), pid(2), pid(3)] {
            var expected = original(id)
            let actual = try XCTUnwrap(music.fields(id))
            expected.location = actual.location  // 파일 위치는 Music이 다시 정리
            XCTAssertEqual(actual, expected, "\(id)")
        }
        XCTAssertEqual(try database.appliedTrackIDs(), [])
        XCTAssertEqual(try decision(pid(1)), .rejected)
        XCTAssertEqual(try database.jobs().first?.kind, .undo)
        XCTAssertEqual(try database.jobs().first?.undoOfJobID, jobID)
        XCTAssertNil(try service.createUndoJob(.job(jobID)), "이미 되돌린 작업")
        XCTAssertNil(try service.createUndoJob(.job(undoID)), "되돌리기 작업 자체는 되돌리지 않는다")
    }

    func testUndoSingleTrackAndAlbum() async throws {
        let service = makeService()
        let jobID = try await createJob(service)
        try await service.run(jobID: jobID)

        try await service.run(jobID: try XCTUnwrap(try service.createUndoJob(.track(jobID: jobID, pid(3)))))
        XCTAssertEqual(music.fields(pid(3))?.album, "")
        XCTAssertEqual(music.fields(pid(1))?.artist, "아이유", "다른 곡은 그대로")

        try await service.run(jobID: try XCTUnwrap(try service.createUndoJob(.album(jobID: jobID, albumGroupKey: "아이유\u{1F}꽃갈피 둘"))))
        XCTAssertEqual(music.fields(pid(1))?.artist, "")
        XCTAssertEqual(music.fields(pid(2))?.artworkCount, 0)
        XCTAssertEqual(music.fields(sibling)?.artworkCount, 1, "참고로 쓴 곡의 커버는 건드리지 않는다")
    }

    func testUndoSkipsValuesEditedAfterApply() async throws {
        let service = makeService()
        let jobID = try await createJob(service, [pid(1)])
        try await service.run(jobID: jobID)
        music.edit(pid(1)) { $0.artist = "사용자가 다시 고침" }
        let undoID = try XCTUnwrap(try service.createUndoJob(.job(jobID)))
        let summary = try await service.run(jobID: undoID)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(music.fields(pid(1))?.artist, "사용자가 다시 고침")
        XCTAssertEqual(try database.appliedTrackIDs(), [pid(1).hex], "되돌리지 않았으니 적용 상태로 남는다")
    }

    /// Phase 3 실측: Music이 일부 필드 쓰기를 무시한 곡(검증 실패)도 나머지 필드는 되돌린다
    func testUndoRestoresVerifyFailedTrack() async throws {
        music.ignoredFields = [.trackCount]
        let service = makeService()
        let jobID = try await createJob(service, [pid(1)])
        try await service.run(jobID: jobID)
        XCTAssertEqual(try result(jobID, pid(1)).state, .verifyFailed)
        XCTAssertEqual(music.fields(pid(1))?.artist, "아이유")

        let undoID = try XCTUnwrap(try service.createUndoJob(.job(jobID)))
        let summary = try await service.run(jobID: undoID)
        XCTAssertEqual(summary.verified, 1)
        XCTAssertEqual(music.fields(pid(1))?.artist, "")
        XCTAssertEqual(music.fields(pid(1))?.artworkCount, 0)
    }

    func testReplacedArtworkIsBackedUpAndRestored() async throws {
        let originalArtwork = makeJPEG(width: 640, height: 640)
        music.setArtworkData(pid(2), [originalArtwork])
        music.edit(pid(2)) { _ in }
        var policies = WritePolicies()
        policies.set(.replaceIfDifferent, for: .artwork)
        let service = makeService(policies: policies)
        // 스캔 당시에도 커버가 있었던 것으로 맞춘다
        var track = libraryTrack(pid(2))
        track.hasArtwork = true
        let jobID = (try await service.createJob(kind: .manual, proposals: [proposal(pid(2))], tracks: [pid(2): track]))!
        try await service.run(jobID: jobID)
        XCTAssertEqual(music.artworkList(pid(2)).count, 1)
        XCTAssertNotEqual(music.artworkList(pid(2)).first, originalArtwork)

        try await service.run(jobID: try XCTUnwrap(try service.createUndoJob(.job(jobID))))
        XCTAssertEqual(music.artworkList(pid(2)), [originalArtwork], "백업해 둔 원래 커버로 복원")
    }
}
