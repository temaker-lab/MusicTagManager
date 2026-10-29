import XCTest
@testable import MTMCore

final class PlaylistScopeTests: XCTestCase {
    // 폴더 F1 ⊃ (P1, 폴더 F2 ⊃ P2), 스마트 S, 일반 P3
    private let catalog = LibraryCatalog(playlists: [
        LibraryPlaylist(id: pid(100), name: "보관함", systemRole: .library, itemIDs: (1...9).map(pid)),
        LibraryPlaylist(id: pid(10), name: "F1", kind: .folder, itemIDs: [1, 2, 3, 4].map(pid)),
        LibraryPlaylist(id: pid(11), parentID: pid(10), name: "P1", itemIDs: [1, 2].map(pid)),
        LibraryPlaylist(id: pid(12), parentID: pid(10), name: "F2", kind: .folder, itemIDs: [2, 3, 4].map(pid)),
        LibraryPlaylist(id: pid(13), parentID: pid(12), name: "P2", itemIDs: [2, 3, 4].map(pid)),
        LibraryPlaylist(id: pid(20), name: "S", kind: .smart, itemIDs: [4, 5].map(pid)),
        LibraryPlaylist(id: pid(30), name: "P3", itemIDs: [5, 6, 5].map(pid)),
        LibraryPlaylist(id: pid(40), name: "빈 폴더", kind: .folder, itemIDs: [7].map(pid)),
    ])

    func testDuplicatesAcrossPlaylistsCountedOnce() {
        let scope = PlaylistScope.resolve([pid(11), pid(13), pid(20)], in: catalog)
        XCTAssertEqual(scope.trackIDs, [1, 2, 3, 4, 5].map(pid))
        XCTAssertEqual(scope.duplicatesRemoved, 2)  // 2와 4가 한 번씩 중복
    }

    func testDuplicateWithinPlaylistCountedOnce() {
        let scope = PlaylistScope.resolve([pid(30)], in: catalog)
        XCTAssertEqual(scope.trackIDs, [5, 6].map(pid))
        XCTAssertEqual(scope.duplicatesRemoved, 1)
    }

    func testNestedFolderExpandsAllDescendants() {
        let scope = PlaylistScope.resolve([pid(10)], in: catalog)
        XCTAssertEqual(Set(scope.expandedPlaylists.map(\.name)), ["F1", "P1", "F2", "P2"])
        XCTAssertEqual(scope.trackIDs, [1, 2, 3, 4].map(pid))
        // 폴더 자신의 합집합 항목은 세지 않으므로 중복은 P1·P2가 겹친 2번 곡뿐
        XCTAssertEqual(scope.duplicatesRemoved, 1)
        XCTAssertFalse(scope.memberships.contains { $0.playlistID == pid(10) || $0.playlistID == pid(12) })
    }

    func testSelectingFolderAndChildDoesNotDoubleCount() {
        let scope = PlaylistScope.resolve([pid(10), pid(13)], in: catalog)
        XCTAssertEqual(scope.trackIDs, [1, 2, 3, 4].map(pid))
        XCTAssertEqual(scope.expandedPlaylists.count, 4)
    }

    func testSmartPlaylistItemsIncluded() {
        XCTAssertEqual(PlaylistScope.resolve([pid(20)], in: catalog).trackIDs, [4, 5].map(pid))
    }

    func testFolderWithoutChildrenUsesOwnItems() {
        XCTAssertEqual(PlaylistScope.resolve([pid(40)], in: catalog).trackIDs, [pid(7)])
    }

    func testReconcileSeparatesDeletedPlaylists() {
        let (valid, removed) = PlaylistScope.reconcile(selected: [pid(11), pid(999), pid(20)], in: catalog)
        XCTAssertEqual(valid, [pid(11), pid(20)])
        XCTAssertEqual(removed, [pid(999)])
    }

    func testAncestors() {
        XCTAssertEqual(catalog.ancestors(of: pid(13)), [pid(12), pid(10)])
        XCTAssertEqual(catalog.ancestors(of: pid(30)), [])
    }
}
