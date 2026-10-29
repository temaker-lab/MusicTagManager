import XCTest
@testable import MTMCore

/// 적용을 마친 변경이 대시보드 현황(완비·정리 대상·누락 항목)에 바로 반영되는지
final class AppliedOverlayTests: XCTestCase {
    private let writtenAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func outcome(_ tracks: [LibraryTrack]) -> ScanOutcome {
        let checker = CompletenessChecker()
        var stats = ScanStats()
        let evaluated = tracks.map { EvaluatedTrack(track: $0, result: checker.evaluate($0, fileExists: alwaysExists)) }
        evaluated.forEach { stats.add($0.result) }
        stats.scopeTotal = evaluated.count
        return ScanOutcome(selection: [], removedPlaylistNames: [], tracks: evaluated, stats: stats,
                           duration: 0, timings: ScanTimings(), finishedAt: writtenAt)
    }

    private func track(_ n: UInt64, album: String?, artwork: Bool, modified: Date? = nil) -> LibraryTrack {
        LibraryTrack(id: pid(n), title: "곡 \(n)", artist: "가수", album: album, durationMs: 200_000, hasArtwork: artwork,
                     fileURL: URL(fileURLWithPath: "/m/\(n).mp3"), modifiedDate: modified)
    }

    private func verified(_ n: UInt64, album: String, artwork: Bool, undone: Bool = false) -> ApplyResultRecord {
        var change = TrackChange(values: ["album": .text(album)])
        if artwork { change.artwork = .set(path: "/a.jpg", source: "itunes") }
        return ApplyResultRecord(jobID: 1, persistentID: pid(n).hex, albumGroupKey: nil, label: "곡 \(n)", state: .verified,
                                 plan: .undo(sourceJobID: 0), change: change, errorMessage: nil,
                                 undoneByJobID: undone ? 2 : nil, updatedAt: writtenAt)
    }

    func testVerifiedChangesMoveTracksToComplete() {
        // 1: 완비, 2·3·4: 앨범·커버 없음
        let scan = outcome([track(1, album: "A", artwork: true), track(2, album: nil, artwork: false),
                            track(3, album: nil, artwork: false), track(4, album: nil, artwork: false)])
        XCTAssertEqual(scan.stats.complete, 1)
        XCTAssertEqual(scan.stats.incomplete, 3)

        let attempts = [
            pid(2).hex: verified(2, album: "B", artwork: true),           // 모두 채움 → 완비
            pid(3).hex: verified(3, album: "C", artwork: false),          // 커버는 못 찾음 → 여전히 정리 대상(커버만 누락)
            pid(4).hex: verified(4, album: "D", artwork: true, undone: true), // 되돌림 → 그대로
        ]
        let effective = scan.applyingVerifiedChanges(attempts, rules: CompletenessRules())
        XCTAssertEqual(effective.stats.complete, 2)
        XCTAssertEqual(effective.stats.incomplete, 2)
        XCTAssertEqual(effective.stats.missingCounts[.album], 1)
        XCTAssertEqual(effective.stats.missingCounts[.artwork], 2)
        XCTAssertEqual(effective.stats.scopeTotal, 4)
        XCTAssertEqual(effective.tracks.first { $0.id == pid(2) }?.track.album, "B")
    }

    func testLaterEditInMusicWins() {
        // 적용 뒤 Music에서 다시 고친 곡(수정 시각이 더 늦음)은 보관함 값을 그대로 쓴다
        let scan = outcome([track(2, album: nil, artwork: false, modified: writtenAt.addingTimeInterval(60))])
        let effective = scan.applyingVerifiedChanges([pid(2).hex: verified(2, album: "B", artwork: true)], rules: CompletenessRules())
        XCTAssertEqual(effective.stats.incomplete, 1)
    }
}
