import MTMCore
import SwiftUI

struct PlaylistPickerView: View {
    @Bindable var model: PlaylistPickerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("pp.intro"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("pp.search"), text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            List {
                Section(L("pp.myPlaylists")) {
                    if model.isLoading && model.roots.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    OutlineGroup(model.visibleRoots, children: \.children) { node in
                        row(node.playlist)
                    }
                }
                if let library = model.libraryPlaylist, model.searchText.isEmpty {
                    Section {
                        row(library, title: L("pp.wholeLibraryRow"))
                    } footer: {
                        Text(L("pp.wholeLibraryFooter"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            selectedBar
        }
    }

    /// 지금 선택된 플레이리스트 (✕로 바로 뺄 수 있음)
    private var selectedBar: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(L("pp.selected")).font(.callout.weight(.semibold))
            if model.selectedPlaylists.isEmpty {
                Text(L("common.none")).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.selectedPlaylists) { playlist in
                        HStack(spacing: 4) {
                            Text(playlist.systemRole == .library ? L("dash.wholeLibrary") : playlist.name).lineLimit(1)
                            Button {
                                model.deselect(playlist.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(L("pp.removeFromSelection"))
                        }
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                    }
                }
            }
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            if !model.selectedPlaylists.isEmpty {
                Button(L("pp.deselectAll")) { model.deselectAll() }
                    .buttonStyle(.link)
            }
        }
    }

    private func row(_ playlist: LibraryPlaylist, title: String? = nil) -> some View {
        let covered = model.isCoveredByAncestor(playlist.id)
        return HStack {
            Toggle(isOn: Binding(
                get: { model.isSelected(playlist.id) },
                set: { _ in model.toggle(playlist) }
            )) {
                HStack {
                    Image(systemName: icon(for: playlist))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(title ?? playlist.name)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(covered)
            .help(covered ? L("pp.coveredByAncestor") : "")
            Spacer()
            Text(model.countText(for: playlist.id))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(L("pp.selectOnly")) { model.selectOnly(playlist) }
                .buttonStyle(.link)
                .font(.callout)
                .opacity(model.selection == [playlist.id] ? 0 : 1)
                .disabled(model.selection == [playlist.id])
                .help(L("pp.selectOnly.help"))
        }
        .contextMenu {
            Button(L("pp.selectOnly")) { model.selectOnly(playlist) }
        }
    }

    private func icon(for playlist: LibraryPlaylist) -> String {
        if playlist.systemRole == .library { return "music.note.house" }
        switch playlist.kind {
        case .folder: return "folder"
        case .smart: return "gearshape"
        default: return "music.note.list"
        }
    }
}
