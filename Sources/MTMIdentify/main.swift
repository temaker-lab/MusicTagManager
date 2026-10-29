// 실제 보관함으로 식별 결과 점검 (보관함 읽기 전용, 외부 API 호출, 결과는 지정한 DB에만 저장)
// 사용: MTMIdentify [--db 경로] [--limit 그룹수] [--force] 플레이리스트 이름...
import Foundation
import MTMCore

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    defer { args.removeSubrange(index...index + 1) }
    return args[index + 1]
}
let dbPath = option("--db") ?? FileManager.default.temporaryDirectory.appendingPathComponent("mtm-identify.sqlite").path
let limit = option("--limit").flatMap(Int.init)
let force = args.contains("--force")
args.removeAll { $0 == "--force" }
let contact = ProcessInfo.processInfo.environment["MTM_CONTACT"] ?? "temzzang@gmail.com"

let reader = LibraryReader()
let catalog = try await reader.loadCatalog()
let chosen = catalog.playlists.filter { args.contains($0.name) }
guard !chosen.isEmpty else { print("플레이리스트 이름을 지정하세요"); exit(1) }

let database = try AppDatabase.open(at: URL(fileURLWithPath: dbPath))
try database.replaceSelection(chosen)
let scan = try await ScanService(source: reader, database: database).scan(rules: CompletenessRules(), catalog: catalog)
print("범위 \(scan.stats.scopeTotal)곡, 정리 대상 \(scan.stats.incomplete)곡")

let http = HTTPClient(cache: ResponseCache(database: database))
let acoustID = AcoustIDProvider.makeIfConfigured(http: http)
print("AcoustID: \(acoustID == nil ? "비활성" : "사용")")
let service = IdentificationService(
    database: database, musicBrainz: MusicBrainzProvider(http: http, contact: contact),
    itunes: ITunesSearchProvider(http: http), acoustID: acoustID)
let summary = try await service.identify(scope: scan.tracks, force: force, maxGroups: limit) { p in
    print("  [\(p.completedTracks)/\(p.totalTracks)] \(p.currentLabel)")
}
print(String(format: "\n식별: 그룹 %d, 곡 %d, %.1fs — ", summary.groups, summary.tracks, summary.duration)
      + ConfidenceLevel.allCases.map { "\($0.label) \(summary.levels[$0] ?? 0)" }.joined(separator: " / ")
      + " (채울 값 없음 \(summary.skipped), 오류 \(summary.errors))")

let tracks = Dictionary(uniqueKeysWithValues: scan.tracks.map { ($0.id.hex, $0) })
for p in try database.proposals().sorted(by: { $0.albumGroupKey < $1.albumGroupKey }) {
    guard let e = tracks[p.persistentID] else { continue }
    let t = e.track
    print("\n● \(t.title) / \(t.artist ?? "∅") / \(t.album ?? "∅")  누락=\(e.result.missing.map(\.label))")
    print("  → \(p.title ?? "-") / \(p.artist ?? "-") / \(p.album ?? "-") [\(p.year.map(String.init) ?? "-"), \(p.trackNo ?? 0)/\(p.trackCount ?? 0), 디스크 \(p.discNo ?? 0)] 커버=\(p.artworkRef?.prefix(40) ?? "-")")
    print("  \(p.confidenceLevel.label) \(p.confidenceScore)점 \(p.decision.rawValue) — \(p.evidence.reasons.joined(separator: ", "))\(p.evidence.error.map { " 오류: \($0)" } ?? "")")
}
