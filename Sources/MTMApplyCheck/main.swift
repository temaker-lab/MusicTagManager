// ⚠️ 테스트 보관함 전용 실제 쓰기 점검
// 사용: MTMApplyCheck --db 경로 [--limit 그룹수] [--min-level HIGH|MEDIUM|LOW] apply 플레이리스트
//       MTMApplyCheck --db 경로 undo          (되돌릴 변경이 남은 모든 작업 되돌리기)
//       MTMApplyCheck --db 경로 resume        (끝나지 않은 작업 이어서)
//       MTMApplyCheck --db 경로 cancel        (끝나지 않은 작업의 대기 항목 취소)
//       MTMApplyCheck --db 경로 status        (작업 이력 출력)
import Foundation
import MTMCore

setvbuf(stdout, nil, _IONBF, 0)  // 진행 상황을 바로 보이게 (강제 종료 시점 확인용)
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    defer { args.removeSubrange(index...index + 1) }
    return args[index + 1]
}
guard let dbPath = option("--db") else { print("--db 경로가 필요합니다"); exit(1) }
let limit = option("--limit").flatMap(Int.init)
let minLevel = ConfidenceLevel(rawValue: option("--min-level") ?? "MEDIUM") ?? .medium
let forceIdentify = args.contains("--force")
let dryRun = args.contains("--dry-run")
args.removeAll { $0 == "--force" || $0 == "--dry-run" }
guard let command = args.first else { print("apply | undo | resume | status"); exit(1) }

let music = AppleScriptMusic()
let libraryCount = try await music.libraryTrackCount()
guard libraryCount <= 3_000 else {
    print("현재 보관함 곡 \(libraryCount)개: 메인 보관함으로 보여 중단합니다 (테스트 보관함으로 바꾸세요)")
    exit(1)
}
print("테스트 보관함 곡 \(libraryCount)개")

let database = try AppDatabase.open(at: URL(fileURLWithPath: dbPath))
let workDirectory = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
let service = ApplyService(
    database: database, music: music, writer: LibraryWriter(music: music, maxLibraryTracks: 3_000),
    artwork: ArtworkService(directory: workDirectory.appendingPathComponent("mtm-artwork"), music: music),
    backupDirectory: workDirectory.appendingPathComponent("mtm-backup"), rules: CompletenessRules(), policies: WritePolicies())

func printJob(_ jobID: Int64) throws {
    for item in try database.applyResults(jobID: jobID) {
        let fields = item.change?.fields.map(\.label).joined(separator: ", ") ?? "-"
        print("  [\(item.state.rawValue)] \(item.label) — 변경: \(fields)\(item.errorMessage.map { " (\($0))" } ?? "")")
    }
}

func run(_ jobID: Int64) async throws {
    let summary = try await service.run(jobID: jobID) { progress in
        print("  \(progress.done)/\(progress.total) \(progress.label)")
    }
    print("작업 #\(jobID): 완료 \(summary.verified), 검증 실패 \(summary.verifyFailed), 실패 \(summary.failed), 건너뜀 \(summary.skipped), 남음 \(summary.unfinished)")
    try printJob(jobID)
}

switch command {
case "apply":
    let reader = LibraryReader()
    let catalog = try await reader.loadCatalog()
    let chosen = catalog.playlists.filter { args.dropFirst().contains($0.name) }
    guard !chosen.isEmpty else { print("플레이리스트 이름을 지정하세요"); exit(1) }
    try database.replaceSelection(chosen)
    let scan = try await ScanService(source: reader, database: database).scan(rules: CompletenessRules(), catalog: catalog)
    print("범위 \(scan.stats.scopeTotal)곡, 정리 대상 \(scan.stats.incomplete)곡")
    let http = HTTPClient(cache: ResponseCache(database: database))
    _ = try await IdentificationService(
        database: database, musicBrainz: MusicBrainzProvider(http: http, contact: "temzzang@gmail.com"),
        itunes: ITunesSearchProvider(http: http), acoustID: AcoustIDProvider.makeIfConfigured(http: http)
    ).identify(scope: scan.tracks, force: forceIdentify, maxGroups: limit)
    let order: [ConfidenceLevel] = [.high, .medium, .low]
    let allowed = Set(order.prefix(through: order.firstIndex(of: minLevel) ?? 0))
    let proposals = try database.proposals().filter { allowed.contains($0.confidenceLevel) && $0.decision == .pending }
    let tracks = Dictionary(uniqueKeysWithValues: scan.tracks.map { ($0.id, $0.track) })
    if dryRun {
        for p in proposals.sorted(by: { $0.confidenceScore > $1.confidenceScore }) {
            let t = PersistentID(hex: p.persistentID).flatMap { tracks[$0] }
            print("[\(p.confidenceLevel.rawValue) \(p.confidenceScore)] \(t?.title ?? "?") / \(t?.artist ?? "∅") / \(t?.album ?? "∅")")
            print("    → \(p.title ?? "-") / \(p.artist ?? "-") / \(p.album ?? "-") #\(p.trackNo ?? 0) 커버=\(p.artworkRef?.prefix(12) ?? "-") | \(p.evidence.reasons.joined(separator: ", "))")
        }
        exit(0)
    }
    guard let jobID = try await service.createJob(kind: .manual, proposals: proposals, tracks: tracks) else {
        print("적용할 제안이 없습니다"); exit(0)
    }
    print("작업 #\(jobID): \(proposals.count)곡 적용 시작")
    try await run(jobID)
case "undo":
    // 되돌릴 변경이 남은 모든 적용 작업을 최신 순으로 되돌린다
    var undoneAny = false
    for job in try database.jobs() where job.kind != .undo {
        guard let id = job.id, let undoID = try service.createUndoJob(.job(id)) else { continue }
        print("작업 #\(id) 되돌리기 → 작업 #\(undoID)")
        try await run(undoID)
        undoneAny = true
    }
    if !undoneAny { print("되돌릴 작업이 없습니다") }
case "cancel":
    for id in try database.unfinishedJobIDs() {
        let summary = try service.cancel(jobID: id)
        print("작업 #\(id) 취소: 남은 쓰는 중 \(summary.unfinished)")
    }
case "resume":
    let unfinished = try database.unfinishedJobIDs()
    print("끝나지 않은 작업: \(unfinished)")
    for id in unfinished { try await run(id) }
case "status":
    for job in try database.jobs() {
        print("작업 #\(job.id ?? 0) \(job.kind.rawValue) 완료=\(job.finishedAt != nil) 적용 \(job.applied) 실패 \(job.failed) 건너뜀 \(job.skipped)")
        try printJob(job.id ?? 0)
    }
default:
    print("알 수 없는 명령: \(command)")
}
