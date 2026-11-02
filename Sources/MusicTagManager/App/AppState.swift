import AppKit
import Foundation
import MTMCore
import Observation

/// 대시보드 표의 한 행
struct TrackRow: Identifiable, Hashable {
    let id: PersistentID
    let title: String
    let artist: String
    let album: String
    let completeness: Completeness
    let missing: [RequiredField]
    let missingText: String
    let statusText: String
    let location: String
    /// 처리 상태 정렬용 순위 (완비 0 < 검토 대기 1 < 적용 실패 2 < 적용 완료 3)
    let processRank: Int
    /// 처리 상태 표시 (완비 / 검토 대기 / 적용 완료 / 적용 실패)
    let processStatusText: String

    init(_ evaluated: EvaluatedTrack, process: (rank: Int, text: String)? = nil) {
        let track = evaluated.track
        id = track.id
        title = Normalizer.clean(track.title)
        artist = Normalizer.clean(track.artist)
        album = Normalizer.clean(track.album)
        completeness = evaluated.result.completeness
        missing = evaluated.result.missing
        missingText = evaluated.result.missing.map(\.label).joined(separator: ", ")
        statusText = evaluated.result.completeness.label
        location = track.fileURL.map { $0.pathComponents.suffix(3).joined(separator: "/") } ?? "—"
        processRank = process?.rank ?? 0
        processStatusText = process?.text ?? evaluated.result.completeness.label
    }
}

/// 식별 결과 표의 한 행
struct ProposalRow: Identifiable, Hashable {
    let id: PersistentID
    let albumGroupKey: String
    let currentTitle: String
    let currentArtist: String
    let currentAlbum: String
    let hasArtwork: Bool
    /// 1순위 커버 후보 (`track:` · `itunes:` · `caa:` · `file:`)
    let artworkRef: String?
    let level: ConfidenceLevel
    let score: Int
    let levelText: String
    let current: String
    let title: String
    let artist: String
    let album: String
    let artwork: String
    /// 지금 적용하면 실제로 바뀔 항목 (현재 쓰기 정책 기준)
    let writes: Set<ProposalField>
    let writesText: String
    let decision: ProposalDecision
    let status: RowStatus
    /// 정렬·검색용 상태 이름
    let decisionText: String
    let reasons: String

    var isApplicable: Bool { !writes.isEmpty && decision != .rejected && status != .applied }

    /// 검토 대기함에 둘 곡 (사용자 결정이 필요한 곡)
    var needsReview: Bool {
        switch status {
        case .failed: return true
        case .pending, .override: return isApplicable
        default: return false
        }
    }

    var isUnidentified: Bool {
        if case .unidentified = status { return true } else { return false }
    }

    enum RowStatus: Hashable {
        case applied
        case failed(reason: String)
        case pending
        case override
        case unidentified(reason: String?)
        case nothingToChange(reason: String?)
        case rejected

        var text: String {
            switch self {
            case .applied: return L("status.applied")
            case .failed: return L("status.failed")
            case .pending: return L("status.pending")
            case .override: return L("status.override")
            case .unidentified: return L("status.unidentified")
            case .nothingToChange: return L("status.nothingToChange")
            case .rejected: return L("status.rejected")
            }
        }

        /// 클릭하면 보여 줄 설명
        var detail: String? {
            switch self {
            case .failed(let reason): return reason
            case .nothingToChange(let reason): return reason
            case .rejected: return L("reason.rejectedDetail")
            case .unidentified(let reason): return reason
            default: return nil
            }
        }
    }

    /// 상태: 마지막 식별(또는 직접 수정) 이후의 적용 결과와 지금 값 기준 미리보기로 정한다
    static func status(proposal: ProposalRecord, preview: (fields: [ProposalField], reason: String?),
                       attempt: ApplyResultRecord?) -> RowStatus {
        if proposal.decision == .rejected { return .rejected }
        // 식별을 다시 실행하기 전의 적용 결과·되돌린 결과는 상태에 반영하지 않는다
        if let attempt, attempt.undoneByJobID == nil, attempt.updatedAt >= proposal.identifiedAt {
            switch attempt.state {
            case .failed, .verifyFailed, .skippedChanged:
                return .failed(reason: attempt.errorMessage ?? attempt.state.label)
            case .verified, .skippedNothing:
                // 검증된 적용은 텍스트·숫자 필드를 '적용 당시 계획대로' 이미 반영했다. 적용 후 현재 값으로 다시 계산한
                // preview가 (적용 때 '다른 판' 보호로 의도적으로 제외한 트랙 수·디스크 번호 등을) 트랙 번호가 바뀌며
                // 다시 제안하더라도 실패로 보지 않는다 — 적용 시점 기준과 동일하게 판정한다.
                // 적용 뒤에도 '남은 것'으로 볼 수 있는 건 커버뿐이다(이미지라 못 찾았을 수 있어 별도로 남김).
                let written = Set(attempt.state == .verified ? attempt.change?.fields ?? [] : [])
                let remaining = preview.fields.filter { $0 == .artwork && !written.contains($0) }
                if remaining.isEmpty { return .applied }
                // 적용했지만 커버를 찾지 못해 아직 남음
                let labels = remaining.map(\.label).joined(separator: ", ")
                return .failed(reason: attempt.errorMessage ?? Lf("reason.remaining", labels))
            case .planned, .writing, .cancelled:
                break
            }
        }
        if proposal.decision == .userOverride { return preview.fields.isEmpty ? .nothingToChange(reason: preview.reason) : .override }
        if proposal.confidenceLevel == .none {
            let noCandidate = L("reason.noCandidate")
            var reasons: [String] = []
            if let error = proposal.evidence.error { reasons.append(Lf("reason.errorPrefix", error)) }
            for reason in proposal.evidence.reasons {
                let localized = localizeEvidenceReason(reason)
                if localized != noCandidate { reasons.append(localized) }
            }
            if reasons.isEmpty { return .unidentified(reason: L("reason.noCandidateDetail")) }
            let detail = reasons.map { "• \($0)" }.joined(separator: "\n")
            return .unidentified(reason: detail)
        }
        if preview.fields.isEmpty { return .nothingToChange(reason: preview.reason) }
        return .pending
    }

    init(_ proposal: ProposalRecord, track: LibraryTrack?, attempt: ApplyResultRecord?, rules: CompletenessRules,
         policies: WritePolicies, artworkChecks: [String: ArtworkCheckRecord], allowLowResolutionArtwork: Bool) {
        let usableArtwork = proposal.usableArtworkCandidates(checks: artworkChecks, allowLowResolution: allowLowResolutionArtwork)
        id = PersistentID(hex: proposal.persistentID) ?? PersistentID(0)
        albumGroupKey = proposal.albumGroupKey
        currentTitle = Normalizer.clean(track?.title)
        currentArtist = Normalizer.clean(track?.artist)
        currentAlbum = Normalizer.clean(track?.album)
        hasArtwork = track?.hasArtwork ?? false
        // 확인 결과 쓸 수 없는 후보(이미지 없음 등)는 표시·적용에서 뺀다
        artworkRef = usableArtwork.first
        level = proposal.confidenceLevel
        score = proposal.confidenceScore
        levelText = "\(proposal.confidenceLevel.label) \(proposal.confidenceScore)"
        current = track.map { [Normalizer.clean($0.title), Normalizer.clean($0.artist), Normalizer.clean($0.album)]
            .map { $0.isEmpty ? "∅" : $0 }.joined(separator: " · ") } ?? ""
        title = proposal.title ?? ""
        artist = proposal.artist ?? ""
        album = proposal.album ?? ""
        artwork = usableArtwork.first.map(ArtworkService.sourceLabel) ?? ""
        let preview = track.map {
            proposal.preview(current: $0, rules: rules, policies: policies, artworkChecks: artworkChecks,
                             allowLowResolutionArtwork: allowLowResolutionArtwork)
        } ?? ([], L("reason.noTrackInfo"))
        writes = Set(preview.fields)
        writesText = preview.fields.isEmpty ? (preview.reason ?? "") : preview.fields.map(\.label).joined(separator: ", ")
        decision = proposal.decision
        status = Self.status(proposal: proposal, preview: preview, attempt: attempt)
        decisionText = status.text
        if let error = proposal.evidence.error {
            reasons = Lf("reason.errorPrefix", error)
        } else {
            reasons = proposal.evidence.reasons.map(localizeEvidenceReason).joined(separator: ", ")
        }
    }
}

/// 진행 중인 작업 (total == 0이면 진행률을 알 수 없는 단계)
struct Activity: Equatable {
    var title: String
    var done = 0
    var total = 0
    var detail = ""

    var fraction: Double? { total > 0 ? min(1, Double(done) / Double(total)) : nil }
    var countText: String { total > 0 ? "\(done)/\(total)" : "" }
}

/// 적용 완료 알림 내용
struct CompletionNotice: Equatable {
    let title: String
    let summary: String
    let isWarning: Bool
}

/// 직접 수정 편집 창의 값 (숫자도 문자열로 입력받음)
struct EditableValues: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var albumArtist = ""
    var genre = ""
    var year = ""
    var trackNumber = ""
    var trackCount = ""
    var discNumber = ""
    var discCount = ""
    /// 표시용
    var currentSummary = ""
    var hasArtwork = false
    var proposedArtwork: String?

    var fieldValues: [ProposalField: FieldValue] {
        var values: [ProposalField: FieldValue] = [:]
        for (field, value) in [(ProposalField.title, title), (.artist, artist), (.album, album), (.albumArtist, albumArtist), (.genre, genre)] {
            values[field] = .text(value)
        }
        for (field, value) in [(ProposalField.year, year), (.trackNumber, trackNumber), (.trackCount, trackCount),
                               (.discNumber, discNumber), (.discCount, discCount)] {
            values[field] = .number(Int(value.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        return values
    }

    /// 숫자 칸에 숫자가 아닌 값이 있으면 그 항목 이름
    var invalidNumbers: [String] {
        [(L("field.year"), year), (L("field.trackNumber"), trackNumber), (L("field.trackCount"), trackCount), (L("field.discNumber"), discNumber), (L("field.discCount"), discCount)]
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty && Int($0.1.trimmingCharacters(in: .whitespaces)) == nil }
            .map(\.0)
    }
}

/// 작업 이력의 한 작업
struct JobRow: Identifiable, Hashable {
    let id: Int64
    let title: String
    let startedAt: Date
    let summary: String
    let isFinished: Bool
    let canUndo: Bool
    let isUndo: Bool
    /// 작업한 곡 (앨범·단독 곡 구분 없이 한 목록)
    let items: [Item]
    /// 실제로 처리한 곡 수 (취소·대기 제외)
    let trackCount: Int

    struct Item: Identifiable, Hashable {
        /// 작업마다 고유 (같은 곡이 여러 작업에 있어도 목록 식별자가 겹치지 않게)
        let id: String
        let persistentID: String
        let label: String
        let state: ApplyState
        let message: String?
        let changedFields: String
        let undone: Bool
    }

    init(_ job: JobRecord, results: [ApplyResultRecord], hasSnapshots: Bool = true) {
        id = job.id ?? 0
        isUndo = job.kind == .undo
        let jobNo = id
        if isUndo {
            var t = Lf("history.job.undo", jobNo)
            if let source = job.undoOfJobID { t += Lf("history.job.undoOf", source) }
            title = t
        } else {
            title = Lf("history.job.apply", jobNo)
        }
        startedAt = job.startedAt
        isFinished = job.finishedAt != nil
        var parts: [String] = [Lf("count.songs", job.total), Lf("history.summary.done", job.applied)]
        if job.failed > 0 { parts.append(Lf("history.summary.failed", job.failed)) }
        if job.skipped > 0 { parts.append(Lf("history.summary.skipped", job.skipped)) }
        if !isFinished { parts.append(L("history.summary.unfinished")) }
        summary = parts.joined(separator: " · ")
        // 보존 기간이 지나 스냅샷이 정리된 작업은 되돌릴 수 없다
        canUndo = job.kind != .undo && hasSnapshots && results.contains { $0.state.wrote && $0.undoneByJobID == nil }
        let jobID = id
        items = results.map { result in
            Item(id: "\(jobID)-\(result.persistentID)", persistentID: result.persistentID, label: result.label,
                 state: result.state, message: result.errorMessage,
                 changedFields: result.change?.fields.map(\.label).joined(separator: ", ") ?? "",
                 undone: result.undoneByJobID != nil)
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        trackCount = job.total
    }
}

/// 전역 상태. View는 이 객체와 ViewModel을 통해서만 Core를 사용한다.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case launching, onboarding, ready
        case failed(String)
    }

    var phase: Phase = .launching
    var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            // 언어가 바뀌면 전역 지역화 관리자에 반영하고, 미리 계산해 둔 행 문자열(상태·누락 항목 등)도 다시 만든다
            if oldValue.language != settings.language {
                LocalizationManager.shared.language = settings.language
                // Sparkle 업데이트 대화상자 등 시스템 UI 언어도 맞춘다 (다음 실행부터 반영)
                syncSystemUILanguage(settings.language)
                reloadProposals()
                reloadJobs()
            }
            // 쓰기 정책이 바뀌면 '적용 시 변경' 미리보기도 다시 계산
            if oldValue.writePolicies != settings.writePolicies { reloadProposals() }
            // 스냅샷 보존 기간을 줄이면 즉시 정리
            if oldValue.snapshotRetentionDays != settings.snapshotRetentionDays { pruneOldSnapshots() }
        }
    }
    private(set) var catalog: LibraryCatalog?
    private(set) var selectedIDs: [PersistentID] = []
    /// 대시보드·식별에 쓰는 검사 결과 (앱에서 적용을 마친 변경을 반영한 현황)
    private(set) var lastScan: ScanOutcome?
    /// 보관함에서 읽은 그대로의 검사 결과
    @ObservationIgnored private var rawScan: ScanOutcome?
    private(set) var rows: [TrackRow] = []
    private(set) var isScanning = false
    var errorMessage: String?
    private(set) var isIdentifying = false
    /// 진행 중인 작업 하나 (검사·커버 상태 확인·식별·커버 후보 확인·적용·결과 정리). 단계가 바뀌면 새로 센다.
    private(set) var activity: Activity?
    private(set) var lastIdentification: IdentificationSummary?
    private(set) var proposalRows: [ProposalRow] = []
    private(set) var isApplying = false
    private(set) var lastJobSummary: JobSummary?
    private(set) var jobRows: [JobRow] = []
    private(set) var appliedCount = 0
    private(set) var completionNotice: CompletionNotice?

    /// 다른 화면에서 열 탭 요청
    var requestedTab: DashboardViewModel.Tab?
    @ObservationIgnored private var artworkImages: [String: NSImage] = [:]
    /// 삭제되어 자동 해제된 플레이리스트 (알림 1회)
    var removedPlaylistNotice: [String] = []

    let reader = LibraryReader()
    /// Music 앱 명령 (전용 스레드에서 직렬 실행). 쓰기는 ApplyService → LibraryWriter로만
    @ObservationIgnored let music = AppleScriptMusic()
    @ObservationIgnored private let settingsStore = SettingsStore()
    @ObservationIgnored var database: AppDatabase?
    @ObservationIgnored private var scanner: ScanService?

    init() {
        // MTMCore의 enum 레이블도 앱 언어를 따르게 연결 (반드시 설정 로드 전에)
        MTMLoc.translate = { L($0) }
        settings = settingsStore.load()
        LocalizationManager.shared.language = settings.language
        // Sparkle 등 시스템 제공 UI가 저장된 언어를 따르도록 (업데이터 시작 전인 이 시점에 설정)
        syncSystemUILanguage(settings.language)
        do {
            let database = try AppDatabase.openDefault()
            self.database = database
            scanner = ScanService(source: reader, database: database)
            selectedIDs = try database.selectedPlaylistIDs()
        } catch {
            phase = .failed(Lf("err.dbOpen", error.localizedDescription))
        }
    }

    var selectedPlaylists: [LibraryPlaylist] {
        guard let catalog else { return [] }
        return selectedIDs.compactMap(catalog.playlist)
    }

    func bootstrap() async {
        guard phase == .launching else { return }
        guard settings.onboardingCompleted else {
            phase = .onboarding
            return
        }
        phase = .ready
        await refresh()
        // 강제 종료 등으로 끝나지 않은 작업은 이어서 마친다 (사용자가 시작한 작업)
        await resumeUnfinishedJobs()
        // 보존 기간이 지난 되돌리기 스냅샷·백업 파일 정리
        pruneOldSnapshots()
    }

    /// 보존 기간(설정)이 지난 되돌리기 스냅샷과 그 백업 파일을 정리한다. 0일이면 무제한 보관.
    /// 끝나지 않은(재개 대상) 작업의 스냅샷은 건드리지 않는다.
    func pruneOldSnapshots() {
        guard let database, settings.snapshotRetentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.snapshotRetentionDays, to: Date()) ?? .distantPast
        guard let paths = try? database.pruneSnapshots(olderThan: cutoff), !paths.isEmpty else { return }
        let fm = FileManager.default
        for path in paths { try? fm.removeItem(atPath: path) }
        // 비워진 원본 파일 백업 폴더(Backup/Files/jobN) 정리
        let filesDir = AppDatabase.defaultDirectory.appendingPathComponent("Backup/Files", isDirectory: true)
        if let subdirs = try? fm.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil) {
            for dir in subdirs where ((try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? false) {
                try? fm.removeItem(at: dir)
            }
        }
        reloadJobs()
        Log.apply.info("오래된 스냅샷 정리: 파일 \(paths.count)개")
    }

    /// 보관함 읽기 (온보딩에서 '미디어 및 Apple Music' 권한 확인 겸용)
    @discardableResult
    func loadCatalog() async throws -> LibraryCatalog {
        let catalog = try await reader.loadCatalog()
        self.catalog = catalog
        return catalog
    }

    /// 보관함을 다시 읽고 선택 범위를 검사한다. 기본은 바뀐 곡만, `full`이면 전체를 다시 판정한다.
    func refresh(full: Bool = false) async {
        guard let scanner, !isScanning else { return }
        isScanning = true
        let ownsActivity = activity == nil
        if ownsActivity { activity = Activity(title: L("activity.scanning")) }
        defer {
            isScanning = false
            if ownsActivity { activity = nil }
        }
        do {
            let catalog = try await loadCatalog()
            let outcome = try await scanner.scan(rules: settings.rules, catalog: catalog, forceFull: full)
            apply(outcome)
            errorMessage = nil
        } catch {
            Log.app.error("스캔 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// 작업 이력이 있는가 (플레이리스트를 바꿀 때 초기화 안내용)
    var hasHistory: Bool { !jobRows.isEmpty || appliedCount > 0 || !proposalRows.isEmpty }

    /// 대상 플레이리스트를 바꾼다. 바뀌면 작업 이력·정리 완료 수·식별 결과를 초기화한다 (이전 변경은 되돌릴 수 없게 됨).
    func updateSelection(_ ids: Set<PersistentID>) async {
        guard let database, let catalog else { return }
        // 카탈로그 순서를 유지해 저장
        let playlists = catalog.playlists.filter { ids.contains($0.id) }
        let changed = Set(playlists.map(\.id)) != Set(selectedIDs)
        do {
            try database.replaceSelection(playlists)
            selectedIDs = try database.selectedPlaylistIDs()
            if changed { try database.clearHistory() }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
        reloadJobs()
    }

    func playlistCounts() async -> [PersistentID: PlaylistCounts] {
        guard let scanner else { return [:] }
        let catalog: LibraryCatalog
        if let current = self.catalog {
            catalog = current
        } else if let loaded = try? await loadCatalog() {
            catalog = loaded
        } else {
            return [:]
        }
        return await scanner.playlistCounts(catalog: catalog, rules: settings.rules)
    }

    func finishOnboarding(selection: Set<PersistentID>) async {
        settings.onboardingCompleted = true
        phase = .ready
        await updateSelection(selection)
    }

    func updateRules(_ rules: CompletenessRules) async {
        guard rules != settings.rules else { return }
        settings.rules = rules
        await refresh()
    }

    /// 검토 대기 수 (사용자 결정이 필요한 곡)
    var reviewCount: Int { reviewRows(includeAll: false).count }

    /// 검토 대기함 목록. 기본은 사용자 결정이 필요한 모든 곡(검토 대기·직접 수정·적용 실패)으로,
    /// 신뢰도(높음·보통·낮음)와 무관하게 보여 식별 결과 화면의 '검토 대기' 수와 일치한다.
    /// `includeAll`이면 아직 적용하지 않은 모든 곡(식별 실패·바꿀 값 없음 포함)까지 보여 준다.
    func reviewRows(includeAll: Bool) -> [ProposalRow] {
        proposalRows.filter { row in
            if includeAll { return row.status != .applied }
            return row.needsReview
        }
    }

    var proposalCounts: [ConfidenceLevel: Int] {
        Dictionary(grouping: proposalRows, by: \.level).mapValues(\.count)
    }

    /// 식별 결과 중 적용을 마친 곡 수 (신뢰도별). 다시 식별하지 않아도 적용 결과에 따라 바로 바뀐다.
    var appliedProposalCounts: [ConfidenceLevel: Int] {
        Dictionary(grouping: proposalRows.filter { $0.status == .applied }, by: \.level).mapValues(\.count)
    }

    var unidentifiedCount: Int { proposalRows.filter(\.isUnidentified).count }

    enum IdentifyOutcome { case completed, offline, failed, skipped }

    /// 정리 대상 곡을 식별해 제안값을 만든다. Music 보관함은 수정하지 않는다.
    /// 식별을 실행하면 직접 수정을 뺀 모든 상태가 검토 대기로 초기화된다.
    @discardableResult
    func identify(force: Bool = false) async -> IdentifyOutcome {
        guard let database, lastScan != nil, !isIdentifying, !isScanning, !isApplying else { return .skipped }
        isIdentifying = true
        defer {
            isIdentifying = false
            activity = nil
        }
        // ITLibrary가 커버가 있다고 한 정리 대상 곡은 Music에서 실제 커버를 한 번 확인한다
        await verifyArtworkTruth()
        guard let scan = lastScan else { return .skipped }

        let service = makeIdentificationService(database)
        var outcome = IdentifyOutcome.completed
        activity = Activity(title: L("activity.identify"))
        do {
            lastIdentification = try await service.identify(scope: scan.tracks, force: force) { progress in
                Task { @MainActor [weak self] in
                    // 이미 다음 단계로 넘어갔으면 늦게 도착한 진행 알림은 버린다
                    guard let self, self.activity?.title == L("activity.identify") else { return }
                    self.activity = Activity(title: L("activity.identify"), done: progress.completedTracks, total: progress.totalTracks,
                                             detail: progress.currentLabel)
                }
            }
            errorMessage = nil
        } catch let error as HTTPError where error == .offline {
            outcome = .offline
            errorMessage = L("err.identifyOffline")
        } catch {
            Log.app.error("식별 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = Lf("err.identifyFailed", error.localizedDescription)
            outcome = .failed
        }
        activity = Activity(title: L("activity.tidying"))
        reloadProposals()
        if outcome == .completed { await checkArtworkCandidates() }
        return outcome
    }

    private func makeIdentificationService(_ database: AppDatabase) -> IdentificationService {
        let http = HTTPClient(cache: ResponseCache(database: database))
        let acoustID = settings.identification.useAcoustID ? AcoustIDProvider.makeIfConfigured(http: http) : nil
        return IdentificationService(
            database: database,
            musicBrainz: MusicBrainzProvider(http: http, contact: settings.musicBrainzContact),
            itunes: ITunesSearchProvider(http: http), acoustID: acoustID, settings: settings.identification)
    }

    /// 직접 입력한 제목·가수·앨범을 단서로 그 곡만 다시 식별한다 (보관함은 수정하지 않음).
    /// - Returns: 새 식별 결과 행. 실패하면 nil (errorMessage에 사유)
    func reidentify(_ id: PersistentID, title: String, artist: String, album: String) async -> ProposalRow? {
        guard let database, let evaluated = lastScan?.tracks.first(where: { $0.id == id }),
              !isIdentifying, !isApplying, !isScanning else { return nil }
        // 진행 표시는 직접 수정 화면 안에서 보여주므로 메인 앱 진행바(activity)는 켜지 않는다
        isIdentifying = true
        defer { isIdentifying = false }
        do {
            let record = try await makeIdentificationService(database)
                .identifyWithHints(evaluated, title: title, artist: artist, album: album)
            // 커버가 필요한 곡이면 후보를 미리 확인해 쓸 수 없는 커버를 뺀다
            if !evaluated.track.hasArtwork, !record.artworkCandidates.isEmpty {
                _ = await makeArtworkService().prepareWithReport(record.artworkCandidates)
            }
            errorMessage = nil
        } catch let error as HTTPError where error == .offline {
            errorMessage = L("err.reidentifyOffline")
            return nil
        } catch {
            errorMessage = Lf("err.reidentifyFailed", error.localizedDescription)
            return nil
        }
        reloadProposals()
        return proposalRows.first { $0.id == id }
    }

    /// 검사에서 ‘커버 있음’으로 나온 정리 대상 곡의 실제 커버를 Music에서 확인한다.
    /// ITLibrary는 곡에 커버가 없어도 같은 앨범의 캐시 이미지를 돌려줄 때가 있다(실측: 적용 시 140곡 오판).
    func verifyArtworkTruth() async {
        guard let database, let scan = lastScan else { return }
        let known = (try? database.artworkTruth()) ?? [:]
        let targets = scan.tracks.filter { $0.result.completeness == .incomplete && $0.track.hasArtwork && known[$0.id.hex] == nil }
            .map(\.id)
        guard !targets.isEmpty else { return }
        var checked = 0
        activity = Activity(title: L("activity.coverStatus"), done: 0, total: targets.count)
        for chunk in stride(from: 0, to: targets.count, by: 10).map({ Array(targets[$0..<min($0 + 10, targets.count)]) }) {
            guard let fields = try? await music.readTracks(chunk) else { break }
            try? database.recordArtworkTruth(fields.mapValues { $0.artworkCount > 0 })
            checked += chunk.count
            activity = Activity(title: L("activity.coverStatus"), done: checked, total: targets.count)
        }
        activity = Activity(title: L("activity.tidying"))
        await refresh()
    }

    func reloadProposals() {
        guard let database, let records = try? database.proposals() else { return }
        let applied = (try? database.appliedTrackIDs()) ?? []
        let attempts = (try? database.latestApplyAttempts()) ?? [:]
        // 적용 결과를 현황에 반영 (완비·정리 대상·누락 항목이 다시 검사하지 않아도 바로 바뀜)
        if let rawScan {
            lastScan = rawScan.applyingVerifiedChanges(attempts, rules: settings.rules)
        }
        let scopeIDs = Set((lastScan?.tracks ?? []).map(\.id.hex))
        appliedCount = applied.filter(scopeIDs.contains).count
        let checks = (try? database.artworkChecks()) ?? [:]
        let tracks = Dictionary(uniqueKeysWithValues: (lastScan?.tracks ?? []).map { ($0.id.hex, $0.track) })
        proposalRows = records.map {
            ProposalRow($0, track: tracks[$0.persistentID], attempt: attempts[$0.persistentID],
                        rules: settings.rules, policies: settings.writePolicies, artworkChecks: checks,
                        allowLowResolutionArtwork: settings.allowLowResolutionArtwork)
        }
        // 곡별 처리 상태(완비/검토 대기/적용 완료/적용 실패)를 곡 목록 행에 반영
        let rowByID = Dictionary(proposalRows.map { ($0.id.hex, $0) }, uniquingKeysWith: { first, _ in first })
        rows = (lastScan?.tracks ?? []).map { TrackRow($0, process: Self.processStatus(row: rowByID[$0.id.hex], applied: applied.contains($0.id.hex))) }
    }

    /// 곡의 처리 상태를 (정렬 순위, 표시 텍스트)로 (완비 < 검토 대기 < 적용 실패 < 적용 완료)
    private static func processStatus(row: ProposalRow?, applied: Bool) -> (rank: Int, text: String)? {
        if let row {
            switch row.status {
            case .applied: return (3, L("status.applied"))
            case .failed: return (2, L("status.failed"))
            case .pending, .override: return (1, L("status.pending"))
            case .unidentified, .nothingToChange, .rejected: break
            }
        }
        if applied { return (3, L("status.applied")) }
        return nil  // 완비 (기본값)
    }

    // MARK: - 적용·되돌리기

    /// 확인 결과를 DB에 남기는 커버 서비스
    func makeArtworkService() -> ArtworkService {
        // 커버 '지연 후보'(itunes-song:)를 풀 iTunes 검색기 — 응답은 캐시해 재실행 시 빠르게
        let itunes = database.map { ITunesSearchProvider(http: HTTPClient(cache: ResponseCache(database: $0))) }
        return ArtworkService(directory: AppDatabase.defaultDirectory.appendingPathComponent("Artwork", isDirectory: true), music: music,
                              lowResolutionMinimum: settings.allowLowResolutionArtwork ? 300 : nil, checkStore: database,
                              itunes: itunes)
    }

    /// 쓸 수 없는 것으로 확인된 커버 후보를 뺀 제안 (적용·자동 적용용)
    func withUsableArtwork(_ proposals: [ProposalRecord]) -> [ProposalRecord] {
        let checks = (try? database?.artworkChecks()) ?? [:]
        return proposals.map { proposal in
            var copy = proposal
            copy.artworkCandidates = proposal.usableArtworkCandidates(checks: checks, allowLowResolution: settings.allowLowResolutionArtwork)
            return copy
        }
    }

    /// 식별 직후 커버가 필요한 곡의 후보를 미리 내려받아 확인한다 → ‘적용 시 변경’에서 쓸 수 없는 커버를 뺄 수 있다
    func checkArtworkCandidates() async {
        guard let database, let scan = lastScan else { return }
        let needsArtwork = Set(scan.tracks.filter { !$0.track.hasArtwork && $0.result.completeness == .incomplete }.map(\.id.hex))
        let checks = (try? database.artworkChecks()) ?? [:]
        let pending = ((try? database.proposals()) ?? []).filter { proposal in
            needsArtwork.contains(proposal.persistentID)
                && proposal.artworkCandidates.contains { !ArtworkService.isTrusted($0) && checks[$0] == nil }
        }
        guard !pending.isEmpty else { return }
        let service = makeArtworkService()
        // 같은 앨범의 곡은 후보가 같아 한 번만 내려받는다
        var seen = Set<[String]>()
        let unique = pending.filter { seen.insert($0.artworkCandidates).inserted }
        activity = Activity(title: L("activity.coverCandidates"), done: 0, total: unique.count)
        for (index, proposal) in unique.enumerated() {
            _ = await service.prepareWithReport(proposal.artworkCandidates)
            activity = Activity(title: L("activity.coverCandidates"), done: index + 1, total: unique.count)
        }
        activity = Activity(title: L("activity.tidying"))
        reloadProposals()
    }

    func makeApplyService() -> ApplyService? {
        guard let database else { return nil }
        let base = AppDatabase.defaultDirectory
        return ApplyService(
            database: database, music: music,
            writer: LibraryWriter(music: music, maxLibraryTracks: settings.writeGuardEnabled ? AppSettings.writeGuardLimit : nil),
            artwork: makeArtworkService(),
            backupDirectory: base.appendingPathComponent("Backup", isDirectory: true),
            rules: settings.rules, policies: settings.writePolicies, fullFileBackup: settings.fullFileBackup)
    }

    /// 선택한 제안을 Music에 적용한다 (스냅샷 → 쓰기 → 검증)
    func apply(_ ids: Set<PersistentID>) async {
        guard let database, let service = makeApplyService(), let scan = lastScan, !isApplying else { return }
        let tracks = Dictionary(uniqueKeysWithValues: scan.tracks.map { ($0.id, $0.track) })
        // 미리보기상 바뀔 값이 있는 곡만 (식별 실패·거절 제외). '채울 값 없음'이었어도 교체 정책으로 바뀔 값이 있으면 포함
        let applicable = Set(proposalRows.filter { ids.contains($0.id) && $0.isApplicable }.map(\.id.hex))
        let proposals = withUsableArtwork(((try? database.proposals()) ?? []).filter { applicable.contains($0.persistentID) })
        do {
            guard let jobID = try await service.createJob(kind: .manual, proposals: proposals, tracks: tracks) else {
                errorMessage = L("err.noApplicable")
                return
            }
            await run(jobID, service: service)
            if settings.showApplyCompletionAlert, let summary = lastJobSummary, summary.jobID == jobID {
                showCompletionAlert(summary)
            }
        } catch {
            errorMessage = Lf("err.createJobFailed", error.localizedDescription)
        }
    }

    /// 선택·전체 적용이 끝나면 앱 창 가운데에 결과 알림 (‘다시 표시하지 않기’ 체크박스 포함)
    private func showCompletionAlert(_ summary: JobSummary) {
        var lines = [Lf("completion.done", summary.verified)]
        if summary.verifyFailed + summary.failed > 0 { lines.append(Lf("completion.failed", summary.verifyFailed + summary.failed)) }
        if summary.skipped > 0 { lines.append(Lf("completion.skipped", summary.skipped)) }
        if summary.unfinished > 0 { lines.append(Lf("completion.unfinished", summary.unfinished)) }
        completionNotice = CompletionNotice(
            title: summary.unfinished > 0 ? L("completion.title.unfinished") : L("completion.title.done"),
            summary: lines.joined(separator: " · "),
            isWarning: summary.failed + summary.verifyFailed + summary.unfinished > 0)
    }

    func dismissCompletionNotice(suppress: Bool) {
        if suppress { settings.showApplyCompletionAlert = false }
        completionNotice = nil
    }

    // MARK: - 직접 수정

    /// 편집 창의 시작 값: 제안값이 있으면 제안값, 없으면 지금 값
    func editableValues(for id: PersistentID) -> EditableValues {
        let track = lastScan?.tracks.first { $0.id == id }?.track
        let proposal = (try? database?.proposals())?.first { $0.persistentID == id.hex }
        func text(_ proposed: String?, _ current: String?) -> String { Normalizer.clean(proposed ?? current) }
        func number(_ proposed: Int?, _ current: Int?) -> String {
            let value = proposed ?? current ?? 0
            return value > 0 ? String(value) : ""
        }
        return EditableValues(
            title: text(proposal?.title, track?.title), artist: text(proposal?.artist, track?.artist),
            album: text(proposal?.album, track?.album), albumArtist: text(proposal?.albumArtist, track?.albumArtist),
            genre: text(proposal?.genre, track?.genre), year: number(proposal?.year, track?.year),
            trackNumber: number(proposal?.trackNo, track?.trackNumber), trackCount: number(proposal?.trackCount, track?.trackCount),
            discNumber: number(proposal?.discNo, track?.discNumber), discCount: number(proposal?.discCount, track?.discCount),
            currentSummary: track.map { "\(Normalizer.clean($0.title)) · \(Normalizer.clean($0.artist)) · \(Normalizer.clean($0.album))" } ?? "",
            hasArtwork: track?.hasArtwork ?? false,
            proposedArtwork: proposal?.artworkRef.map { ArtworkService.sourceLabel($0) })
    }

    /// 미리 듣기용 로컬 오디오 파일 경로. 실제로 존재하는 파일일 때만 돌려준다 (클라우드 전용·경로 없음 → nil).
    func previewAudioURL(for id: PersistentID) -> URL? {
        guard let url = lastScan?.tracks.first(where: { $0.id == id })?.track.fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 입력된 제목·가수·앨범으로 앨범커버를 검색한다 (iTunes → Deezer). 결과가 없으면 빈 배열.
    func searchAlbumCovers(title: String, artist: String, album: String) async -> [AlbumCoverCandidate] {
        guard let database else { return [] }
        let http = HTTPClient(cache: ResponseCache(database: database))
        return await AlbumCoverService(http: http).search(title: title, artist: artist, album: album)
    }

    /// 고른 커버를 임시 파일로 내려받는다 (직접 수정의 커버로 쓰려고). 실패하면 nil.
    func downloadCover(_ candidate: AlbumCoverCandidate) async -> URL? {
        guard let (data, _) = try? await URLSession.shared.data(from: candidate.imageURL),
              NSImage(data: data) != nil else { return nil }
        let ext = candidate.imageURL.pathExtension.isEmpty ? "jpg" : candidate.imageURL.pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 사용자가 입력한 값을 저장하고, 원하면 바로 적용한다
    func saveOverride(for id: PersistentID, values: EditableValues, artworkFile: URL?, applyNow: Bool) async {
        guard let database else { return }
        var copied: URL?
        if let artworkFile {
            // 원본 파일이 옮겨져도 적용할 수 있게 앱 데이터 폴더로 복사
            let directory = AppDatabase.defaultDirectory.appendingPathComponent("Artwork/User", isDirectory: true)
            let target = directory.appendingPathComponent("\(id.hex)-\(UUID().uuidString).\(artworkFile.pathExtension)")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: artworkFile, to: target)
                copied = target
            } catch {
                errorMessage = Lf("err.copyCoverFailed", error.localizedDescription)
                return
            }
        }
        let track = lastScan?.tracks.first { $0.id == id }
        let groupKey = track.map { TrackRecord.albumGroupKey(for: $0.track, missing: $0.result.missing) } ?? "single:\(id.hex)"
        do {
            try database.saveOverride(persistentID: id, albumGroupKey: groupKey, values: values.fieldValues,
                                      artworkFile: copied, keepArtworkCandidates: !(track?.track.hasArtwork ?? false))
        } catch {
            errorMessage = Lf("err.saveFailed", error.localizedDescription)
            return
        }
        reloadProposals()
        if applyNow { await apply([id]) }
    }

    // MARK: - 검수표 (CSV)

    func exportReviewSheet(to url: URL) {
        guard let database, let proposals = try? database.proposals() else { return }
        let tracks = Dictionary(uniqueKeysWithValues: (lastScan?.tracks ?? []).map { ($0.id, $0.track) })
        let statuses = Dictionary(uniqueKeysWithValues: proposalRows.map { ($0.id.hex, $0.status.text) })
        do {
            try ReviewSheet.export(proposals: proposals, tracks: tracks, statuses: statuses).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = Lf("err.exportSheetFailed", error.localizedDescription)
        }
    }

    /// 검수표를 읽어 고친 값은 ‘직접 수정’으로, 거절은 바로 반영한다. 승인 목록은 확인 후 적용하도록 돌려준다.
    func importReviewSheet(from url: URL) -> ReviewSheet.ImportResult? {
        guard let database, let proposals = try? database.proposals() else { return nil }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = Lf("err.importSheetFailed", error.localizedDescription)
            return nil
        }
        let byID = Dictionary(uniqueKeysWithValues: proposals.map { ($0.persistentID, $0) })
        let result = ReviewSheet.parse(text, proposals: byID)
        for (id, values) in result.overrides {
            let proposal = byID[id.hex]
            try? database.saveOverride(persistentID: id, albumGroupKey: proposal?.albumGroupKey ?? "single:\(id.hex)",
                                       values: values, artworkFile: nil, keepArtworkCandidates: true)
        }
        if !result.reject.isEmpty { try? database.reject(result.reject) }
        reloadProposals()
        return result
    }

    // MARK: - 커버 끌어 놓기

    /// 끌어 놓은 이미지를 지정한 곡들의 커버 1순위 후보로 (커버가 없는 곡에만 들어감)
    func setArtwork(_ image: URL, for ids: [PersistentID]) {
        guard let database, !ids.isEmpty else { return }
        let directory = AppDatabase.defaultDirectory.appendingPathComponent("Artwork/User", isDirectory: true)
        let target = directory.appendingPathComponent("drop-\(UUID().uuidString).\(image.pathExtension.isEmpty ? "jpg" : image.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: image, to: target)
            try database.setArtworkFile(target, for: ids)
        } catch {
            errorMessage = Lf("err.setArtworkFailed", error.localizedDescription)
        }
        reloadProposals()
    }

    /// 원본 파일 백업이 차지하는 용량 (바이트)
    func fileBackupSize() -> Int64 {
        let directory = AppDatabase.defaultDirectory.appendingPathComponent("Backup/Files", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// 검토 대기함에서 거절 (Music에는 쓰지 않음)
    func reject(_ ids: Set<PersistentID>) {
        do {
            try database?.reject(Array(ids))
        } catch {
            errorMessage = Lf("err.rejectFailed", error.localizedDescription)
        }
        reloadProposals()
    }

    // MARK: - 커버 미리보기 이미지

    /// `track:`(Music의 커버) · `itunes:`/`caa:`(내려받기) · `file:` 후보를 이미지로 (메모리 캐시)
    func artworkImage(for reference: String) async -> NSImage? {
        if let cached = artworkImages[reference] { return cached }
        var data: Data?
        if reference.hasPrefix("track:"), let id = PersistentID(hex: String(reference.dropFirst(6))) {
            data = try? await music.artworkData(of: id)
        } else if reference.hasPrefix("file:") {
            data = try? Data(contentsOf: URL(fileURLWithPath: String(reference.dropFirst(5))))
        } else if let colon = reference.firstIndex(of: ":"), let url = URL(string: String(reference[reference.index(after: colon)...])) {
            data = try? await URLSession.shared.data(from: url).0
        }
        let image = data.flatMap(NSImage.init(data:))
        artworkImages[reference] = image
        return image
    }

    func undo(_ scope: UndoScope) async {
        guard let service = makeApplyService(), !isApplying else { return }
        do {
            guard let jobID = try service.createUndoJob(scope) else {
                errorMessage = L("err.nothingToUndo")
                return
            }
            await run(jobID, service: service)
        } catch {
            errorMessage = Lf("err.createUndoFailed", error.localizedDescription)
        }
    }

    /// 강제 종료 등으로 끝나지 않은 작업을 이어서 진행한다
    func resumeUnfinishedJobs() async {
        guard let database, let service = makeApplyService(),
              let jobIDs = try? database.unfinishedJobIDs(), !jobIDs.isEmpty else {
            reloadJobs()
            return
        }
        for jobID in jobIDs {
            await run(jobID, service: service)
            if errorMessage != nil { break }
        }
    }

    func run(_ jobID: Int64, service: ApplyService) async {
        isApplying = true
        activity = Activity(title: L("activity.apply"))
        defer {
            isApplying = false
            activity = nil
        }
        guard await Permissions.launchMusicIfNeeded() else {
            errorMessage = L("err.launchMusicFailed")
            reloadJobs()
            return
        }
        var failure: String?
        do {
            lastJobSummary = try await service.run(jobID: jobID) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.activity?.title == L("activity.apply") else { return }
                    self.activity = Activity(title: L("activity.apply"), done: progress.done, total: progress.total, detail: progress.label)
                    // 적용하는 동안에도 대시보드 숫자(정리 완료·검토 대기·식별 결과 남은 곡)를 갱신한다
                    if progress.done == progress.total || progress.done % 5 == 0 { self.reloadProposals() }
                }
            }
        } catch {
            Log.app.error("작업 \(jobID) 중단: \(error.localizedDescription, privacy: .public)")
            failure = Lf("err.jobStopped", error.localizedDescription)
        }
        // 적용 결과를 다시 검사해 완비된 곡은 대상에서 빠지게 한다 (진행 표시는 ‘결과 정리 중’)
        activity = Activity(title: L("activity.tidying"))
        reloadJobs()
        await refresh()
        if let failure { errorMessage = failure }
    }

    func cancel(jobID: Int64) {
        guard let service = makeApplyService(), !isApplying else { return }
        do {
            try service.cancel(jobID: jobID)
        } catch {
            errorMessage = Lf("err.cancelFailed", error.localizedDescription)
        }
        reloadJobs()
        reloadProposals()
    }

    func resume(jobID: Int64) async {
        guard let service = makeApplyService(), !isApplying else { return }
        await run(jobID, service: service)
    }

    func reloadJobs() {
        guard let database, let jobs = try? database.jobs() else { return }
        let withSnapshots = (try? database.jobIDsWithSnapshots()) ?? []
        jobRows = jobs.compactMap { job in
            guard let id = job.id else { return nil }
            return JobRow(job, results: (try? database.applyResults(jobID: id)) ?? [], hasSnapshots: withSnapshots.contains(id))
        }
    }

    var isAcoustIDConfigured: Bool {
        KeychainStore.read(service: AcoustIDProvider.keychainService, account: AcoustIDProvider.keychainAccount) != nil
    }

    func saveAcoustIDKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(service: AcoustIDProvider.keychainService, account: AcoustIDProvider.keychainAccount)
        } else {
            try KeychainStore.write(trimmed, service: AcoustIDProvider.keychainService, account: AcoustIDProvider.keychainAccount)
        }
    }

    private func apply(_ outcome: ScanOutcome) {
        rawScan = outcome
        lastScan = outcome
        rows = outcome.tracks.map { TrackRow($0) }
        selectedIDs = outcome.selection.map(\.id)
        if !outcome.removedPlaylistNames.isEmpty {
            removedPlaylistNotice = outcome.removedPlaylistNames
        }
        reloadProposals()
    }
}
