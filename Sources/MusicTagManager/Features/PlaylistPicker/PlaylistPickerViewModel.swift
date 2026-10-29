import Foundation
import MTMCore
import Observation

struct PlaylistNode: Identifiable, Hashable {
    let playlist: LibraryPlaylist
    let children: [PlaylistNode]?
    var id: PersistentID { playlist.id }
}

/// 플레이리스트 체크박스 트리 (온보딩·설정 공용)
@MainActor
@Observable
final class PlaylistPickerViewModel {
    var selection: Set<PersistentID>
    var searchText = ""
    private(set) var roots: [PlaylistNode] = []
    private(set) var libraryPlaylist: LibraryPlaylist?
    private(set) var counts: [PersistentID: PlaylistCounts] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?
    private var catalog: LibraryCatalog?

    private let state: AppState

    init(state: AppState) {
        self.state = state
        self.selection = Set(state.selectedIDs)
    }

    var hasSelection: Bool { !selection.isEmpty }
    var isDirty: Bool { selection != Set(state.selectedIDs) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await state.loadCatalog()
            self.catalog = catalog
            buildTree(catalog)
            // 삭제된 플레이리스트는 선택에서 뺀다
            selection = selection.filter { catalog.playlist($0) != nil }
            loadError = nil
            counts = await state.playlistCounts()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 검색 중에는 이름이 맞는 항목을 평평한 목록으로 보여 준다.
    var visibleRoots: [PlaylistNode] {
        let query = Normalizer.compareKey(searchText)
        guard !query.isEmpty, let catalog else { return roots }
        return catalog.userPlaylists
            .filter { Normalizer.compareKey($0.name).contains(query) }
            .map { PlaylistNode(playlist: $0, children: nil) }
    }

    func isSelected(_ id: PersistentID) -> Bool {
        selection.contains(id) || isCoveredByAncestor(id)
    }

    /// 상위 폴더가 선택되어 있어 자동 포함된 항목 (체크 해제 불가)
    func isCoveredByAncestor(_ id: PersistentID) -> Bool {
        guard let catalog else { return false }
        return catalog.ancestors(of: id).contains(where: selection.contains)
    }

    func toggle(_ playlist: LibraryPlaylist) {
        if selection.contains(playlist.id) {
            selection.remove(playlist.id)
        } else {
            selection.insert(playlist.id)
            // 폴더를 고르면 하위 항목의 개별 선택은 정리한다 (폴더가 모두 포함)
            if playlist.isFolder, let catalog {
                for child in PlaylistScope.expand([playlist.id], in: catalog) where child.id != playlist.id {
                    selection.remove(child.id)
                }
            }
        }
    }

    func countText(for id: PersistentID) -> String {
        guard let count = counts[id] else { return isLoading ? "" : "…" }
        if let needs = count.needsWork {
            return Lf("pp.countNeeds", count.total, needs)
        }
        return Lf("pp.count", count.total)
    }

    /// 중복 제거된 실제 곡 수는 스캔 후 대시보드에 표시된다.
    var selectionSummary: String {
        let count = selection.count
        return count == 0 ? "선택한 플레이리스트가 없습니다" : "\(count)개 선택됨"
    }

    /// 선택된 플레이리스트 (표시용, 카탈로그 순서)
    var selectedPlaylists: [LibraryPlaylist] {
        guard let catalog else { return [] }
        return catalog.playlists.filter { selection.contains($0.id) }
    }

    func deselect(_ id: PersistentID) { selection.remove(id) }

    func deselectAll() { selection.removeAll() }

    /// 다른 선택을 모두 풀고 이 플레이리스트만 대상으로
    func selectOnly(_ playlist: LibraryPlaylist) { selection = [playlist.id] }

    func apply() async {
        await state.updateSelection(selection)
    }

    private func buildTree(_ catalog: LibraryCatalog) {
        func node(_ playlist: LibraryPlaylist) -> PlaylistNode {
            let children = catalog.children(of: playlist.id).filter { $0.systemRole == nil }.map(node)
            return PlaylistNode(playlist: playlist, children: playlist.isFolder ? children : nil)
        }
        roots = catalog.userPlaylists.filter { $0.parentID == nil }.map(node)
        libraryPlaylist = catalog.playlists.first { $0.systemRole == .library }
    }
}
