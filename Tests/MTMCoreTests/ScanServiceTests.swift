import XCTest
@testable import MTMCore

final class ScanServiceTests: XCTestCase {
    private func makeLibrary() -> FakeLibrary {
        var incomplete = completeTrack(2, title: "No Cover")
        incomplete.hasArtwork = false
        var cloud = completeTrack(4)
        cloud.fileURL = nil
        cloud.isCloud = true
        return FakeLibrary(
            playlists: [
                LibraryPlaylist(id: pid(10), name: "A", itemIDs: [1, 2].map(pid)),
                LibraryPlaylist(id: pid(11), name: "B", itemIDs: [2, 3, 4].map(pid)),
                LibraryPlaylist(id: pid(12), name: "선택 안 함", itemIDs: [5].map(pid)),
            ],
            tracks: [completeTrack(1), incomplete, completeTrack(3), cloud, completeTrack(5)])
    }

    private func select(_ ids: [UInt64], in library: FakeLibrary, database: AppDatabase) throws {
        try database.replaceSelection(ids.compactMap { library.catalog.playlist(pid($0)) })
    }

    func testScanOnlySelectedPlaylistsAndDeduplicates() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10, 11], in: library, database: database)
        let outcome = try await ScanService(source: library, database: database, fileExists: alwaysExists)
            .scan(rules: CompletenessRules())

        XCTAssertEqual(outcome.tracks.map(\.id), [1, 2, 3, 4].map(pid))  // 5번(선택 안 한 목록)은 제외
        XCTAssertEqual(outcome.stats.duplicatesRemoved, 1)
        XCTAssertEqual(outcome.stats.complete, 2)
        XCTAssertEqual(outcome.stats.incomplete, 1)
        XCTAssertEqual(outcome.stats.excludedCloud, 1)
        XCTAssertEqual(outcome.stats.missingCounts[.artwork], 1)

        let stored = try database.trackRecords()
        XCTAssertEqual(stored.count, 4)
        let record = try XCTUnwrap(stored.first { $0.persistentID == pid(2).hex })
        XCTAssertEqual(record.missingFields, [.artwork])
        XCTAssertTrue(record.isEligible)
        XCTAssertEqual(try database.playlistTrackCount(), 5)
    }

    func testRescanOnlyRechecksChangedTracks() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10, 11], in: library, database: database)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)

        let first = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(first.stats.rechecked, 4)

        let readsBefore = library.fullReads
        let second = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(second.stats.rechecked, 0)
        XCTAssertEqual(second.stats.reused, 4)
        XCTAssertEqual(library.fullReads, readsBefore, "변경 없는 곡은 ITLibrary에서 다시 읽지 않아야 함")

        // 사용자가 Music에서 커버를 넣음 → 수정 시각이 바뀐 곡만 재검사
        library.tracksByID[pid(2)]?.hasArtwork = true
        library.tracksByID[pid(2)]?.modifiedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let readsBeforeThird = library.fullReads
        let third = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(third.stats.rechecked, 1)
        XCTAssertEqual(third.stats.incomplete, 0)
        XCTAssertEqual(library.fullReads - readsBeforeThird, 1)

        // 규칙이 바뀌면 전체 재검사
        var rules = CompletenessRules()
        rules.albumPlaceholders.append("Album")
        let fourth = try await service.scan(rules: rules)
        XCTAssertEqual(fourth.stats.rechecked, 4)
        XCTAssertEqual(fourth.stats.incomplete, 3)
    }

    /// 실측: ITLibrary가 곡에 없는 커버(앨범 캐시)를 있다고 보고 → Music에서 읽은 값을 쓴다
    func testArtworkTruthOverridesLibraryFlag() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10], in: library, database: database)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)
        let first = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(first.tracks.first { $0.id == pid(1) }?.result.completeness, .complete)

        try database.recordArtworkTruth([pid(1): false], at: Date(timeIntervalSince1970: 1_700_000_100))
        let second = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(second.tracks.first { $0.id == pid(1) }?.result.missing, [.artwork])

        // 곡이 그 뒤에 바뀌었으면(예: 사용자가 Music에서 커버를 넣음) ITLibrary 값을 다시 쓴다
        library.tracksByID[pid(1)]?.modifiedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let third = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(third.tracks.first { $0.id == pid(1) }?.result.completeness, .complete)
    }

    func testForceFullRereadsEverything() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10, 11], in: library, database: database)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)
        _ = try await service.scan(rules: CompletenessRules())
        let outcome = try await service.scan(rules: CompletenessRules(), forceFull: true)
        XCTAssertEqual(outcome.stats.rechecked, 4)
        XCTAssertEqual(outcome.stats.reused, 0)
    }

    func testReusedTrackKeepsStoredValues() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10], in: library, database: database)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)
        let first = try await service.scan(rules: CompletenessRules())
        let second = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(second.tracks.map(\.track), first.tracks.map(\.track))
        XCTAssertEqual(second.tracks.map(\.result), first.tracks.map(\.result))
    }

    func testDeletedFileIsRechecked() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10], in: library, database: database)
        let missing = LockedSet()
        let service = ScanService(source: library, database: database) { !missing.contains($0.path) }
        _ = try await service.scan(rules: CompletenessRules())
        missing.insert(library.tracksByID[pid(1)]!.fileURL!.path)
        let outcome = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(outcome.stats.rechecked, 1)
        XCTAssertEqual(outcome.stats.excludedMissingFile, 1)
    }

    func testDeletedPlaylistIsRemovedFromSelectionOnce() async throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        try select([10, 11], in: library, database: database)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)
        _ = try await service.scan(rules: CompletenessRules())

        library.playlists.removeAll { $0.id == pid(11) }
        let outcome = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(outcome.removedPlaylistNames, ["B"])
        XCTAssertEqual(outcome.selection.map(\.id), [pid(10)])
        XCTAssertEqual(try database.selectedPlaylistIDs(), [pid(10)])
        // 범위를 벗어난 곡(3, 4)은 DB에서도 삭제
        XCTAssertEqual(Set(try database.trackRecords().map(\.persistentID)), Set([1, 2].map { pid($0).hex }))
        XCTAssertEqual(try database.playlistTrackCount(), 2)

        let again = try await service.scan(rules: CompletenessRules())
        XCTAssertEqual(again.removedPlaylistNames, [])  // 알림은 1회만
    }

    func testReplaceSelectionKeepsOriginalSelectedAt() throws {
        let library = makeLibrary()
        let database = try AppDatabase.inMemory()
        let a = library.catalog.playlist(pid(10))!, b = library.catalog.playlist(pid(11))!
        try database.replaceSelection([a], at: Date(timeIntervalSince1970: 100))
        try database.replaceSelection([a, b], at: Date(timeIntervalSince1970: 200))
        let records = try database.selectedPlaylists()
        XCTAssertEqual(records.map(\.nameAtSelection), ["A", "B"])
        XCTAssertEqual(records[0].selectedAt, Date(timeIntervalSince1970: 100))
    }

    func testPlaylistCounts() async throws {
        let library = makeLibrary()
        let service = ScanService(source: library, database: try AppDatabase.inMemory(), fileExists: alwaysExists)
        let counts = await service.playlistCounts(catalog: library.catalog, rules: CompletenessRules())
        XCTAssertEqual(counts[pid(10)], PlaylistCounts(total: 2, needsWork: 1))
        XCTAssertEqual(counts[pid(11)], PlaylistCounts(total: 3, needsWork: 1))
    }

    /// 수용 기준: 플레이리스트 5,000곡 목록화 3초 이내, 재실행은 변경분만
    func testPerformanceFiveThousandTracks() async throws {
        var tracks: [LibraryTrack] = []
        for i in 1...5_000 {
            var track = completeTrack(UInt64(i), title: "곡 \(i)")
            if i % 3 == 0 { track.hasArtwork = false }
            if i % 7 == 0 { track.album = "Unknown Album" }
            tracks.append(track)
        }
        let library = FakeLibrary(
            playlists: [LibraryPlaylist(id: pid(1_000_000), name: "Big", itemIDs: tracks.map(\.id))],
            tracks: tracks)
        let database = try AppDatabase.open(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("mtm-perf-\(UUID().uuidString).sqlite"))
        try database.replaceSelection(library.playlists)
        let service = ScanService(source: library, database: database, fileExists: alwaysExists)

        let first = try await service.scan(rules: CompletenessRules())
        let second = try await service.scan(rules: CompletenessRules())
        print("5,000곡 첫 스캔 \(first.duration)s, 재스캔 \(second.duration)s")
        XCTAssertEqual(first.stats.scopeTotal, 5_000)
        XCTAssertLessThan(first.duration, 3)
        XCTAssertLessThan(second.duration, 3)
        XCTAssertEqual(second.stats.rechecked, 0)
    }
}

final class LockedSet: @unchecked Sendable {
    private var values = Set<String>()
    private let lock = NSLock()
    func insert(_ value: String) { lock.withLock { _ = values.insert(value) } }
    func contains(_ value: String) -> Bool { lock.withLock { values.contains(value) } }
}
