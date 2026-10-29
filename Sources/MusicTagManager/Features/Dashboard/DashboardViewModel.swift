import Foundation
import MTMCore
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    enum StatusFilter: String, CaseIterable, Identifiable {
        case incomplete = "정리 대상"
        case all = "전체"
        case complete = "완비"
        case excluded = "수정 불가"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .incomplete: return L("completeness.incomplete")
            case .all: return L("filter.all")
            case .complete: return L("completeness.complete")
            case .excluded: return L("filter.excluded")
            }
        }

        func matches(_ completeness: Completeness) -> Bool {
            switch self {
            case .all: return true
            case .incomplete: return completeness == .incomplete
            case .complete: return completeness == .complete
            case .excluded: return completeness.isExcluded
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case tracks = "곡 목록"
        case proposals = "식별 결과"
        case review = "검토 대기함"
        case history = "작업 이력"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tracks: return L("tab.tracks")
            case .proposals: return L("tab.proposals")
            case .review: return L("tab.review")
            case .history: return L("tab.history")
            }
        }
    }

    var tab: Tab = .tracks
    /// 식별 결과 필터 (nil = 전체)
    var proposalLevel: ConfidenceLevel?
    var proposalSortOrder = [KeyPathComparator(\ProposalRow.score, order: .reverse)]
    var proposalSelection = Set<PersistentID>()
    /// 켜면 상태가 ‘검토 대기’인 곡만 보기
    var reviewOnly = false

    var status: StatusFilter = .incomplete
    var missingField: RequiredField?
    var searchText = ""
    var sortOrder = [KeyPathComparator(\TrackRow.album), KeyPathComparator(\TrackRow.title)]
    var selection = Set<PersistentID>()
    /// 켜면 완비 목록에서 중복곡(제목·가수 같은 곡)만 보기
    var showDuplicatesOnly = false

    /// 완비 곡 중 제목·가수가 같은 곡이 2개 이상인 곡들의 ID (중복곡)
    func duplicateCompleteIDs(_ rows: [TrackRow]) -> Set<PersistentID> {
        var groups: [String: [PersistentID]] = [:]
        for row in rows where row.completeness == .complete {
            let key = Normalizer.compareKey(row.title) + "\u{1F}" + Normalizer.compareKey(row.artist)
            groups[key, default: []].append(row.id)
        }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    func filteredRows(_ rows: [TrackRow]) -> [TrackRow] {
        let query = Normalizer.compareKey(searchText)
        let duplicates = (status == .complete && showDuplicatesOnly) ? duplicateCompleteIDs(rows) : nil
        return rows.filter { row in
            guard status.matches(row.completeness) else { return false }
            if let duplicates, !duplicates.contains(row.id) { return false }
            if let field = missingField, !row.missing.contains(field) { return false }
            guard !query.isEmpty else { return true }
            return [row.title, row.artist, row.album, row.location].contains {
                Normalizer.compareKey($0).contains(query)
            }
        }
        .sorted(using: sortOrder)
    }

    func filteredProposals(_ rows: [ProposalRow]) -> [ProposalRow] {
        let query = Normalizer.compareKey(searchText)
        return rows.filter { row in
            if let level = proposalLevel, row.level != level { return false }
            if reviewOnly, row.status != .pending { return false }
            guard !query.isEmpty else { return true }
            return [row.current, row.title, row.artist, row.album].contains { Normalizer.compareKey($0).contains(query) }
        }
        .sorted(using: proposalSortOrder)
    }

    func showProposals(_ level: ConfidenceLevel?) {
        tab = .proposals
        proposalLevel = proposalLevel == level ? nil : level
    }

    /// 누락 항목 집계를 누르면 해당 곡만 보이게
    func showMissing(_ field: RequiredField) {
        tab = .tracks
        status = .incomplete
        missingField = missingField == field ? nil : field
    }

    func showStatus(_ filter: StatusFilter) {
        tab = .tracks
        status = filter
        missingField = nil
    }
}
