import MTMCore
import SwiftUI

/// 앨범 상세: 곡별 현재값 ↔ 제안값, 바뀔 항목, 직접 수정
struct AlbumDetailView: View {
    @Environment(AppState.self) private var state
    let groupKey: String
    let dismiss: () -> Void
    @State private var selection = Set<PersistentID>()
    @State private var editing: DashboardView.EditTarget?
    @State private var isDropTargeted = false

    private var rows: [ProposalRow] {
        state.proposalRows.filter { $0.albumGroupKey == groupKey }.sorted { $0.currentTitle < $1.currentTitle }
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkThumbnail(reference: rows.first(where: \.hasArtwork).map { "track:\($0.id.hex)" }, placeholder: L("art.currentNone"), size: 96)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                ArtworkThumbnail(reference: rows.lazy.compactMap(\.artworkRef).first, placeholder: L("art.dropHere"), size: 96)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2))
                    .onDrop(of: ImageDrop.types, isTargeted: $isDropTargeted) { providers in
                        Task {
                            if let url = await ImageDrop.load(providers) {
                                state.setArtwork(url, for: rows.filter { !$0.hasArtwork }.map(\.id))
                            }
                        }
                        return true
                    }
                    .help(L("review.dropHelp"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(rows.first { !$0.album.isEmpty }?.album ?? rows.first?.currentAlbum ?? "").font(.title2.bold())
                    Text(rows.first { !$0.artist.isEmpty }?.artist ?? "").foregroundStyle(.secondary)
                    Text(Lf("count.songs", rows.count)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Table(rows, selection: $selection) {
                TableColumn(L("col.currentTitle")) { Text($0.currentTitle) }
                TableColumn(L("col.propTitle")) { row in Text(row.title).foregroundStyle(row.writes.contains(.title) ? .primary : .secondary) }
                TableColumn(L("col.propArtist")) { row in Text(row.artist).foregroundStyle(row.writes.contains(.artist) ? .primary : .secondary) }
                TableColumn(L("col.writes")) { Text($0.writesText) }
                TableColumn(L("col.confidence")) { row in LevelBadge(level: row.level, score: row.score) }
                    .width(80)
                TableColumn(L("col.status")) { Text($0.status.text) }
                    .width(90)
            }
            .contextMenu(forSelectionType: PersistentID.self) { ids in
                if let id = ids.first, ids.count == 1 { Button(L("common.directEditEllipsis")) { editing = .init(id: id) } }
            } primaryAction: { ids in
                if let id = ids.first { editing = .init(id: id) }
            }
            Text(L("albumDetail.hint"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("common.directEditEllipsis")) { if let id = selection.first { editing = .init(id: id) } }
                    .disabled(selection.count != 1)
                    .buttonStyle(NeutralActionButtonStyle())
                Spacer()
                Button(L("common.close"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NeutralActionButtonStyle())
                Button(L("albumDetail.rejectAlbum")) {
                    state.reject(Set(rows.map(\.id)))
                    dismiss()
                }
                .buttonStyle(NeutralActionButtonStyle())
                Button(L("albumDetail.approveAlbum")) {
                    let ids = Set(rows.filter(\.isApplicable).map(\.id))
                    dismiss()
                    Task { await state.apply(ids) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rows.contains(where: \.isApplicable) || state.isApplying)
            }
        }
        .padding(20)
        .frame(width: 820, height: 560)
        .sheet(item: $editing) { target in
            ProposalEditView(id: target.id) { editing = nil }
                .environment(state)
        }
    }
}
