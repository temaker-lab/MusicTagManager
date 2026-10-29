import MTMCore
import SwiftUI

/// 검토 대기함의 앨범 카드 하나
struct AlbumCard: Identifiable, Hashable {
    let id: String
    let rows: [ProposalRow]

    var isSingle: Bool { id.hasPrefix("single:") }
    var currentAlbum: String { rows.first?.currentAlbum ?? "" }
    var proposedAlbum: String { rows.first { !$0.album.isEmpty }?.album ?? "" }
    var artist: String { rows.first { !$0.artist.isEmpty }?.artist ?? rows.first?.currentArtist ?? "" }
    /// 가장 낮은 신뢰도 (앨범 전체를 승인할 때의 기준)
    var level: ConfidenceLevel {
        let order: [ConfidenceLevel] = [.none, .low, .medium, .high]
        return rows.map(\.level).min { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! } ?? .none
    }
    var averageScore: Int { rows.isEmpty ? 0 : rows.map(\.score).reduce(0, +) / rows.count }
    var applicableIDs: Set<PersistentID> { Set(rows.filter(\.isApplicable).map(\.id)) }
    var allIDs: Set<PersistentID> { Set(rows.map(\.id)) }
    var changedFields: String {
        let fields = Set(rows.flatMap(\.writes))
        return ProposalField.allCases.filter(fields.contains).map(\.label).joined(separator: ", ")
    }
    var currentArtworkRef: String? { rows.first(where: \.hasArtwork).map { "track:\($0.id.hex)" } }
    var proposedArtworkRef: String? { rows.lazy.compactMap(\.artworkRef).first }
    var failureCount: Int { rows.filter { if case .failed = $0.status { return true } else { return false } }.count }

    var title: String {
        if isSingle, let row = rows.first { return row.title.isEmpty ? row.currentTitle : row.title }
        return proposedAlbum.isEmpty ? currentAlbum : proposedAlbum
    }
}

/// 신뢰도가 낮거나 보통인 곡을 앨범 단위로 모아 한 번에 승인·거절한다.
/// 키보드: ↑↓ 이동 · Return·Space 자세히(더블클릭도) · ⌘Return 승인 · Delete 거절
struct ReviewQueueView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<String>()
    @State private var detail: AlbumCard?
    @State private var confirmRejectAll = false
    @State private var confirmApplyAll = false
    /// 신뢰도 낮음·식별 실패 곡까지 모두 보기
    @AppStorage("reviewIncludeAll") private var includeAll = false
    @FocusState private var focused: Bool

    private var cards: [AlbumCard] {
        let rows = state.reviewRows(includeAll: includeAll)
        let grouped = Dictionary(grouping: rows, by: \.albumGroupKey)
        return grouped.map { AlbumCard(id: $0.key, rows: $0.value.sorted { $0.currentTitle < $1.currentTitle }) }
            .sorted { $0.averageScore != $1.averageScore ? $0.averageScore > $1.averageScore : $0.title < $1.title }
    }

    var body: some View {
        let cards = self.cards
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 곡 수·앨범 수 칩은 폭을 미리 확보해 숫자가 바뀌어도 오른쪽 요소가 밀리지 않게 한다
                countChip(L("review.chip.pending"), cards.reduce(0) { $0 + $1.rows.count })
                countChip(L("review.chip.albums"), cards.count)
                Toggle(L("review.showAll"), isOn: $includeAll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help(L("review.showAll.help"))
                Spacer()
                Button(L("review.approveHighMedium")) {
                    let ids = cards.flatMap(\.rows).filter { [.high, .medium].contains($0.level) && $0.isApplicable }.map(\.id)
                    Task { await state.apply(Set(ids)) }
                }
                .disabled(state.isApplying || !cards.flatMap(\.rows).contains { [.high, .medium].contains($0.level) && $0.isApplicable })
                Button(L("review.approveSelected")) { approve(selectedCards(cards)) }
                    .disabled(selection.isEmpty || state.isApplying)
                    .help("⌘Return")
                Button(L("review.rejectAll")) { confirmRejectAll = true }
                    .disabled(cards.isEmpty || state.isApplying)
                Button(Lf("review.applyAllN", allApplicable(cards).count)) { confirmApplyAll = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(allApplicable(cards).isEmpty || state.isApplying)
                    .help(L("review.applyAll.help"))
            }
            Text(L("review.keyHints"))
                .font(.caption).foregroundStyle(.secondary)
            if cards.isEmpty {
                ContentUnavailableView(L("review.empty.title"), systemImage: "checkmark.seal",
                                       description: Text(L("review.empty.desc")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(cards, selection: $selection) { card in
                    AlbumCardRow(card: card,
                                 approve: { approve([card]) },
                                 reject: { reject([card]) },
                                 showDetail: { detail = card })
                        .tag(card.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { ids in
                    let picked = cards.filter { ids.contains($0.id) }
                    Button(L("common.detail")) { detail = picked.first }.disabled(picked.count != 1)
                    Button(L("common.approve")) { approve(picked) }
                    Button(L("common.reject")) { reject(picked) }
                } primaryAction: { ids in
                    // 더블클릭 → 자세히
                    detail = cards.first { ids.contains($0.id) }
                }
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        approve(selectedCards(cards))
                    } else {
                        detail = selectedCards(cards).first
                    }
                    return .handled
                }
                .onKeyPress(.delete) {
                    reject(selectedCards(cards))
                    return .handled
                }
                .onKeyPress(.space) {
                    detail = selectedCards(cards).first
                    return .handled
                }
                .onAppear {
                    focused = true
                    if selection.isEmpty, let first = cards.first { selection = [first.id] }
                }
            }
        }
        .sheet(item: $detail) { card in
            AlbumDetailView(groupKey: card.id) { detail = nil }
                .environment(state)
        }
        .alert(Lf("review.confirmAll.title", allApplicable(cards).count), isPresented: $confirmApplyAll) {
            Button(L("dash.applyAllConfirm")) {
                let ids = allApplicable(cards)
                Task { await state.apply(ids) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("review.confirmAll.msg"))
        }
        .alert(L("review.confirmReject.title"), isPresented: $confirmRejectAll) {
            Button(L("review.confirmReject.confirm"), role: .destructive) { state.reject(Set(cards.flatMap(\.allIDs))) }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("review.confirmReject.msg"))
        }
    }

    /// 식별 결과의 필터 칩과 같은 테두리 캡슐 모양. 클릭 동작은 없고 폭을 80pt로 고정해 숫자가 바뀌어도 밀리지 않는다.
    private func countChip(_ label: String, _ count: Int) -> some View {
        Button {} label: {
            Text("\(label) \(count)")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 80)
        }
        .buttonStyle(PillButtonStyle(selected: false, compact: true))
        .allowsHitTesting(false)
    }

    private func allApplicable(_ cards: [AlbumCard]) -> Set<PersistentID> {
        cards.reduce(into: Set<PersistentID>()) { $0.formUnion($1.applicableIDs) }
    }

    private func selectedCards(_ cards: [AlbumCard]) -> [AlbumCard] {
        cards.filter { selection.contains($0.id) }
    }

    private func approve(_ cards: [AlbumCard]) {
        let ids = cards.reduce(into: Set<PersistentID>()) { $0.formUnion($1.applicableIDs) }
        guard !ids.isEmpty, !state.isApplying else { return }
        moveSelection(after: cards)
        Task { await state.apply(ids) }
    }

    private func reject(_ cards: [AlbumCard]) {
        let ids = cards.reduce(into: Set<PersistentID>()) { $0.formUnion($1.allIDs) }
        guard !ids.isEmpty else { return }
        moveSelection(after: cards)
        state.reject(ids)
    }

    /// 처리한 카드 다음 카드로 선택을 옮겨 키보드만으로 계속 처리할 수 있게
    private func moveSelection(after handled: [AlbumCard]) {
        let all = cards
        let handledIDs = Set(handled.map(\.id))
        if let lastIndex = all.lastIndex(where: { handledIDs.contains($0.id) }),
           let next = all[(lastIndex + 1)...].first(where: { !handledIDs.contains($0.id) }) ?? all.first(where: { !handledIDs.contains($0.id) }) {
            selection = [next.id]
        } else {
            selection = []
        }
    }
}

private struct AlbumCardRow: View {
    @Environment(AppState.self) private var state
    let card: AlbumCard
    @State private var isDropTargeted = false
    let approve: () -> Void
    let reject: () -> Void
    let showDetail: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                ArtworkThumbnail(reference: card.currentArtworkRef, placeholder: L("art.noCover"))
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                ArtworkThumbnail(reference: card.currentArtworkRef == nil ? card.proposedArtworkRef : nil,
                                 placeholder: card.currentArtworkRef == nil ? L("art.noCandidate") : L("art.keep"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(card.title).font(.headline).lineLimit(1)
                    LevelBadge(level: card.level, score: card.averageScore)
                    if card.failureCount > 0 {
                        Text(Lf("review.failCount", card.failureCount)).font(.caption).foregroundStyle(.red)
                    }
                }
                Text(card.artist).foregroundStyle(.secondary).lineLimit(1)
                if !card.isSingle, !card.currentAlbum.isEmpty, card.currentAlbum != card.proposedAlbum, !card.proposedAlbum.isEmpty {
                    Text("\(card.currentAlbum) → \(card.proposedAlbum)").font(.callout).lineLimit(1)
                }
                Text(Lf("review.tracksAndChanges", card.rows.count, card.changedFields.isEmpty ? L("common.none") : card.changedFields))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(spacing: 6) {
                Button(L("common.approve"), action: approve).disabled(card.applicableIDs.isEmpty)
                Button(L("common.reject"), action: reject)
                Button(L("common.detail"), action: showDetail).buttonStyle(.link)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        // 이미지를 끌어 놓으면 이 앨범의 커버 없는 곡에 지정
        .onDrop(of: ImageDrop.types, isTargeted: $isDropTargeted) { providers in
            Task {
                if let url = await ImageDrop.load(providers) {
                    state.setArtwork(url, for: card.rows.filter { !$0.hasArtwork }.map(\.id))
                }
            }
            return true
        }
        .help(L("review.dropHelp"))
    }
}

struct LevelBadge: View {
    let level: ConfidenceLevel
    let score: Int

    var body: some View {
        Text("\(level.label) \(score)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch level {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .none: return .gray
        }
    }
}

/// 커버 썸네일 (Music·iTunes·Cover Art Archive·파일)
struct ArtworkThumbnail: View {
    @Environment(AppState.self) private var state
    let reference: String?
    var placeholder = L("art.noCover")
    var size: CGFloat = 56
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(placeholder).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: reference) {
            image = nil
            if let reference { image = await state.artworkImage(for: reference) }
        }
    }
}
