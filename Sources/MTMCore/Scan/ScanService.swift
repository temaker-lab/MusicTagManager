import Foundation

public struct EvaluatedTrack: Identifiable, Sendable {
    public let track: LibraryTrack
    public let result: CompletenessResult
    public var id: PersistentID { track.id }
}

public struct ScanStats: Sendable, Equatable {
    /// 범위 내 고유 곡 수
    public var scopeTotal = 0
    public var duplicatesRemoved = 0
    public var complete = 0
    public var incomplete = 0
    public var excludedCloud = 0
    public var excludedMissingFile = 0
    public var excludedUnsupported = 0
    public var missingCounts: [RequiredField: Int] = [:]
    /// 이번에 새로 판정한 곡 / 이전 결과를 그대로 쓴 곡
    public var rechecked = 0
    public var reused = 0

    public var excludedTotal: Int { excludedCloud + excludedMissingFile + excludedUnsupported }

    mutating func add(_ result: CompletenessResult) {
        switch result.completeness {
        case .complete: complete += 1
        case .incomplete: incomplete += 1
        case .excludedCloud: excludedCloud += 1
        case .excludedMissingFile: excludedMissingFile += 1
        case .excludedUnsupported: excludedUnsupported += 1
        }
        for field in result.missing { missingCounts[field, default: 0] += 1 }
    }
}

/// 구간별 소요 시간 (성능 진단용)
public struct ScanTimings: Sendable, CustomStringConvertible {
    public var catalog: TimeInterval = 0
    public var resolve: TimeInterval = 0
    public var tracks: TimeInterval = 0
    public var loadStored: TimeInterval = 0  // DB 읽기 + 수정 시각 조회
    public var evaluate: TimeInterval = 0
    public var persist: TimeInterval = 0

    public var description: String {
        String(format: "카탈로그 %.3f / 범위 %.3f / 곡 변환 %.3f / DB·수정시각 %.3f / 판정 %.3f / DB 쓰기 %.3f",
               catalog, resolve, tracks, loadStored, evaluate, persist)
    }
}

public struct ScanOutcome: Sendable {
    /// 유효한 선택 플레이리스트 (삭제된 것 제외, 펼치기 전)
    public let selection: [LibraryPlaylist]
    /// 선택했지만 보관함에서 사라져 자동 해제된 플레이리스트 이름
    public let removedPlaylistNames: [String]
    public let tracks: [EvaluatedTrack]
    public let stats: ScanStats
    public let duration: TimeInterval
    public let timings: ScanTimings
    public let finishedAt: Date
}

public struct PlaylistCounts: Sendable, Equatable {
    public let total: Int
    /// 정리 필요 곡 수 (전체 라이브러리처럼 미리 계산하지 않은 경우 nil)
    public let needsWork: Int?
}

/// 선택 플레이리스트 범위 수집 → 대상 필터 → 변경분만 DB 반영
public final class ScanService: Sendable {
    private let source: any LibrarySource
    private let database: AppDatabase
    private let fileExists: @Sendable (URL) -> Bool

    public init(source: any LibrarySource, database: AppDatabase,
                fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.source = source
        self.database = database
        self.fileExists = fileExists
    }

    /// - Parameter forceFull: 저장된 결과를 쓰지 않고 범위 전체를 ITLibrary에서 다시 읽어 판정한다.
    public func scan(rules: CompletenessRules, catalog: LibraryCatalog? = nil, forceFull: Bool = false) async throws -> ScanOutcome {
        let started = Date()
        var timings = ScanTimings()
        var mark = started
        func lap(_ keyPath: WritableKeyPath<ScanTimings, TimeInterval>) {
            let now = Date()
            timings[keyPath: keyPath] += now.timeIntervalSince(mark)
            mark = now
        }
        let catalog = if let catalog { catalog } else { try await source.loadCatalog() }
        lap(\.catalog)

        let storedSelection = try database.selectedPlaylists()
        let (valid, removed) = PlaylistScope.reconcile(selected: storedSelection.compactMap(\.id), in: catalog)
        let removedNames = storedSelection.filter { record in removed.contains { $0.hex == record.playlistPersistentID } }
            .map(\.nameAtSelection)

        let scope = PlaylistScope.resolve(valid, in: catalog)
        lap(\.resolve)

        // 증분 재검사: 수정 시각이 같은 곡은 비싼 ITLibrary 속성(location·hasArtworkAvailable, 7천 곡에 약 1초)을
        // 다시 읽지 않고 DB에 저장된 값을 쓴다. 파일 존재 여부만 매번 확인한다.
        let checker = CompletenessChecker(rules: rules)
        let rulesVersion = "\(rules.version).r\(LibraryReader.trackFormatVersion)"
        let stored = try database.storedTracks()
        let modified = await source.modificationDates(for: scope.trackIDs)
        lap(\.loadStored)
        var reusable: [PersistentID: TrackRecord] = [:]
        var needFull: [PersistentID] = []
        for id in scope.trackIDs {
            if !forceFull, let record = stored[id], record.rulesVersion == rulesVersion,
               let date = modified[id], record.modifiedAt == date.timeIntervalSince1970 {
                reusable[id] = record
            } else {
                needFull.append(id)
            }
        }
        var fresh: [PersistentID: LibraryTrack] = [:]
        for track in await source.tracks(for: needFull) { fresh[track.id] = track }
        lap(\.tracks)

        var stats = ScanStats()
        stats.duplicatesRemoved = scope.duplicatesRemoved
        var evaluated: [EvaluatedTrack] = []
        evaluated.reserveCapacity(scope.trackIDs.count)
        var changed: [TrackRecord] = []

        // ITLibrary의 커버 플래그보다 Music에서 직접 읽은 값을 믿는다 (곡이 그 뒤로 바뀌지 않았을 때만)
        let truth = (try? database.artworkTruth()) ?? [:]
        func corrected(_ track: LibraryTrack) -> LibraryTrack {
            guard let known = truth[track.id.hex], known.hasArtwork != track.hasArtwork else { return track }
            if let modified = track.modifiedDate, modified.timeIntervalSince(known.recordedAt) > 2 { return track }
            var copy = track
            copy.hasArtwork = known.hasArtwork
            return copy
        }

        for id in scope.trackIDs {
            let track: LibraryTrack
            let result: CompletenessResult
            if let record = reusable[id], corrected(record.libraryTrack).hasArtwork == record.hasArtwork {
                track = record.libraryTrack
                let exists = track.fileURL.map(fileExists) ?? false
                if exists == record.fileExists {
                    result = record.result
                    stats.reused += 1
                } else {
                    result = checker.evaluate(track) { _ in exists }
                    stats.rechecked += 1
                    changed.append(TrackRecord(track: track, result: result, fileExists: exists,
                                               rulesVersion: rulesVersion, scannedAt: started))
                }
            } else if let freshTrack = fresh[id] ?? reusable[id]?.libraryTrack {
                track = corrected(freshTrack)
                let exists = track.fileURL.map(fileExists) ?? false
                result = checker.evaluate(track) { _ in exists }
                stats.rechecked += 1
                changed.append(TrackRecord(track: track, result: result, fileExists: exists,
                                           rulesVersion: rulesVersion, scannedAt: started))
            } else {
                continue  // 플레이리스트에는 있지만 항목을 읽을 수 없음
            }
            stats.add(result)
            evaluated.append(EvaluatedTrack(track: track, result: result))
        }
        stats.scopeTotal = evaluated.count

        lap(\.evaluate)
        var selectionCounts: [PersistentID: Int] = [:]
        for id in valid {
            selectionCounts[id] = PlaylistScope.resolve([id], in: catalog).trackIDs.count
        }
        try database.persistScan(changed: changed, scopeIDs: Set(evaluated.map(\.id.hex)), memberships: scope.memberships,
                                 removedSelections: removed, selectionCounts: selectionCounts, at: started)
        lap(\.persist)

        let duration = Date().timeIntervalSince(started)
        Log.scan.info("스캔: 범위 \(stats.scopeTotal)곡, 대상 \(stats.incomplete), 재검사 \(stats.rechecked), 재사용 \(stats.reused), \(duration, format: .fixed(precision: 3))s")
        return ScanOutcome(selection: valid.compactMap(catalog.playlist), removedPlaylistNames: removedNames,
                           tracks: evaluated, stats: stats, duration: duration, timings: timings, finishedAt: Date())
    }

    /// 플레이리스트 선택 화면용 "곡 수 / 정리 필요 곡 수". DB에는 기록하지 않는다.
    /// 전체 라이브러리(시스템 목록)는 곡 수만 보여 주고 판정은 하지 않는다.
    public func playlistCounts(catalog: LibraryCatalog, rules: CompletenessRules) async -> [PersistentID: PlaylistCounts] {
        let userIDs = catalog.userPlaylists.filter { $0.parentID == nil }.map(\.id)
        let union = PlaylistScope.resolve(userIDs, in: catalog)
        let checker = CompletenessChecker(rules: rules)
        let rulesVersion = "\(rules.version).r\(LibraryReader.trackFormatVersion)"
        // 스캔과 같은 방식: 수정 시각이 같으면 저장된 판정 결과를 쓰고 나머지만 ITLibrary에서 읽는다
        let stored = (try? database.storedTracks()) ?? [:]
        let modified = await source.modificationDates(for: union.trackIDs)
        var needsWork = Set<PersistentID>()
        var needFull: [PersistentID] = []
        for id in union.trackIDs {
            if let record = stored[id], record.rulesVersion == rulesVersion,
               let date = modified[id], record.modifiedAt == date.timeIntervalSince1970 {
                if record.isEligible { needsWork.insert(id) }
            } else {
                needFull.append(id)
            }
        }
        for track in await source.tracks(for: needFull) where checker.evaluate(track, fileExists: fileExists).completeness.isEligible {
            needsWork.insert(track.id)
        }
        var counts: [PersistentID: PlaylistCounts] = [:]
        for playlist in catalog.playlists {
            let ids = PlaylistScope.resolve([playlist.id], in: catalog).trackIDs
            counts[playlist.id] = PlaylistCounts(
                total: ids.count,
                needsWork: playlist.systemRole == nil ? ids.reduce(0) { $0 + (needsWork.contains($1) ? 1 : 0) } : nil)
        }
        return counts
    }
}

extension ScanOutcome {
    /// 앱에서 적용을 마친(검증된) 변경을 검사 결과에 반영한다.
    /// 보관함 읽기(ITLibrary)가 Music의 변경을 늦게 보여 줘도 대시보드 현황이 적용 결과대로 바로 바뀌게 한다.
    /// 적용 뒤 사용자가 Music에서 곡을 다시 고쳤으면(수정 시각이 더 늦음) 보관함 값을 그대로 쓴다.
    public func applyingVerifiedChanges(_ attempts: [String: ApplyResultRecord], rules: CompletenessRules) -> ScanOutcome {
        let checker = CompletenessChecker(rules: rules)
        var stats = self.stats
        stats.complete = 0
        stats.incomplete = 0
        stats.excludedCloud = 0
        stats.excludedMissingFile = 0
        stats.excludedUnsupported = 0
        stats.missingCounts = [:]
        let tracks = self.tracks.map { evaluated -> EvaluatedTrack in
            var result = evaluated
            if evaluated.result.completeness == .incomplete,
               let attempt = attempts[evaluated.id.hex], attempt.state == .verified, attempt.undoneByJobID == nil,
               let change = attempt.change,
               evaluated.track.modifiedDate.map({ $0.timeIntervalSince(attempt.updatedAt) <= 2 }) ?? true {
                var track = evaluated.track
                func text(_ field: ProposalField) -> String? {
                    if case .text(let value)? = change.value(of: field) { return value }
                    return nil
                }
                if let value = text(.title) { track.title = value }
                if let value = text(.artist) { track.artist = value }
                if let value = text(.album) { track.album = value }
                if let value = text(.albumArtist) { track.albumArtist = value }
                if case .set? = change.artwork { track.hasArtwork = true }
                // 정리 대상이었던 곡은 파일·지원 형식이 확인된 곡
                result = EvaluatedTrack(track: track, result: checker.evaluate(track) { _ in true })
            }
            stats.add(result.result)
            return result
        }
        return ScanOutcome(selection: selection, removedPlaylistNames: removedPlaylistNames, tracks: tracks, stats: stats,
                           duration: duration, timings: timings, finishedAt: finishedAt)
    }
}
