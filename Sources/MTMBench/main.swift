// 실제 Music 보관함 대상 목록화 성능 측정 (읽기 전용, 임시 DB 사용)
// 사용: MTMBench [플레이리스트 이름...]   (이름 생략 시 최상위 사용자 플레이리스트 전체)
import Foundation
import MTMCore

let reader = LibraryReader()
let t0 = Date()
let catalog = try await reader.loadCatalog()
print(String(format: "카탈로그 로드: %.3fs (플레이리스트 %d개)", Date().timeIntervalSince(t0), catalog.playlists.count))

let names = Set(CommandLine.arguments.dropFirst())
let chosen = names.isEmpty
    ? catalog.userPlaylists.filter { $0.parentID == nil }
    : catalog.playlists.filter { names.contains($0.name) }
print("선택: \(chosen.map(\.name).joined(separator: ", "))")

let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("mtm-bench-\(UUID().uuidString).sqlite")
defer { try? FileManager.default.removeItem(at: dbURL) }
let database = try AppDatabase.open(at: dbURL)
try database.replaceSelection(chosen)
let scanner = ScanService(source: reader, database: database)

for label in ["첫 실행", "재실행(변경 없음)"] {
    let outcome = try await scanner.scan(rules: CompletenessRules())
    let s = outcome.stats
    print(String(format: "[%@] %.3fs — 범위 %d곡(중복 %d), 완비 %d, 대상 %d, 수정 불가 %d | 재검사 %d, 재사용 %d",
                 label, outcome.duration, s.scopeTotal, s.duplicatesRemoved, s.complete, s.incomplete,
                 s.excludedTotal, s.rechecked, s.reused))
    print("   구간:", outcome.timings)
    print("   누락:", RequiredField.allCases.map { "\($0.label) \(s.missingCounts[$0] ?? 0)" }.joined(separator: " / "))
}

let t1 = Date()
let counts = await scanner.playlistCounts(catalog: catalog, rules: CompletenessRules())
print(String(format: "플레이리스트별 곡 수/정리 필요 수 계산: %.3fs", Date().timeIntervalSince(t1)))
for playlist in catalog.userPlaylists.prefix(8) {
    if let c = counts[playlist.id] { print("   \(playlist.name): \(c.total)곡 · 정리 필요 \(c.needsWork ?? -1)곡") }
}
