import AppKit
import Charts
import MTMCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var model = DashboardViewModel()
    @State private var picker: PlaylistPickerViewModel?
    @State private var confirmApply = false
    @State private var confirmApplyAll = false
    @State private var editing: EditTarget?
    @State private var importResult: ReviewSheet.ImportResult?
    /// 대상에서 뺄 플레이리스트 (확인 후 적용)
    @State private var removing: LibraryPlaylist?

    struct EditTarget: Identifiable {
        let id: PersistentID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar
            scopeBar
            if let activity = state.activity {
                ActivityBar(activity: activity)
            }
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 10)
            }
            if let scan = state.lastScan {
                overview(scan.stats)
                contentCard
            } else if state.isScanning {
                ProgressView(L("dash.scanning"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(L("dash.noScan.title"), systemImage: "music.note.list",
                                       description: Text(L("dash.noScan.desc")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .padding(.top, 30)  // 창 제목 표시줄(신호등 버튼) 자리
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.text)
        .onChange(of: state.requestedTab) { _, tab in
            if let tab {
                model.tab = tab
                state.requestedTab = nil
            }
        }
        .sheet(item: $picker) { picker in
            PlaylistSelectionSheet(model: picker) { self.picker = nil }
                .environment(state)
        }
        .sheet(item: $editing) { target in
            ProposalEditView(id: target.id) { editing = nil }
                .environment(state)
        }
        .alert(Lf("dash.removePlaylist.title", removing?.name ?? ""), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button(L("common.remove"), role: .destructive) {
                guard let playlist = removing else { return }
                removing = nil
                Task { await state.updateSelection(Set(state.selectedIDs).subtracting([playlist.id])) }
            }
            Button(L("common.cancel"), role: .cancel) { removing = nil }
        } message: {
            Text(state.hasHistory ? PlaylistSelectionSheet.resetMessage : L("dash.removePlaylist.msg"))
        }
        .sheet(item: $importResult) { result in
            ReviewSheetImportView(result: result) { importResult = nil }
                .environment(state)
        }
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [palette.accent, palette.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                Text("MusicTag Manager").font(.title3.bold())
            }
            Spacer(minLength: 20)
            HStack(spacing: 8) {
                ForEach(DashboardViewModel.Tab.allCases) { tab in
                    Button {
                        model.tab = tab
                    } label: {
                        Text(tab == .review && state.reviewCount > 0 ? "\(tab.title) \(state.reviewCount)" : tab.title)
                    }
                    .buttonStyle(PillButtonStyle(selected: model.tab == tab))
                }
            }
            Spacer(minLength: 20)
            AppearanceSwitcher()
        }
    }

    private var scopeBar: some View {
        HStack(spacing: 10) {
            Text(L("dash.scope")).font(.callout.weight(.semibold)).foregroundStyle(palette.secondaryText)
            playlistChips
            Button(L("dash.changePlaylists")) { picker = PlaylistPickerViewModel(state: state) }
                .buttonStyle(PillButtonStyle(selected: false, compact: true))
                .disabled(state.activity != nil)
            Menu {
                Button(L("dash.rescanAll")) { Task { await state.refresh(full: true) } }
            } label: {
                Label(L("dash.rescan"), systemImage: "arrow.clockwise")
            } primaryAction: {
                Task { await state.refresh() }
            }
            .fixedSize()
            .disabled(state.activity != nil)
            .keyboardShortcut("r")
            .help(L("dash.rescan.help"))
            if let scan = state.lastScan {
                Text(Lf("dash.scannedAt", scan.finishedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))))
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 12)
            IdentifyButton(
                disabled: state.activity != nil || (state.lastScan?.stats.incomplete ?? 0) == 0,
                run: { force in Task { await identify(force: force) } }
            )
        }
    }

    /// 선택한 플레이리스트 (많으면 앞의 3개 + 나머지 개수)
    private var playlistChips: some View {
        let playlists = state.selectedPlaylists
        return HStack(spacing: 6) {
            ForEach(playlists.prefix(3)) { playlist in
                HStack(spacing: 5) {
                    Label(playlist.systemRole == .library ? L("dash.wholeLibrary") : playlist.name,
                          systemImage: playlist.isFolder ? "folder" : "music.note.list")
                        .lineLimit(1)
                    if playlists.count > 1 {
                        Button {
                            removing = playlist
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.secondaryText)
                        .disabled(state.activity != nil)
                        .help(L("dash.removeFromScope"))
                    }
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.card))
                .overlay(Capsule().strokeBorder(palette.cardBorder))
            }
            if playlists.count > 3 {
                Text("+\(playlists.count - 3)")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .help(playlists.dropFirst(3).map(\.name).joined(separator: ", "))
            }
        }
    }

    // MARK: - 개요 카드

    private func overview(_ stats: ScanStats) -> some View {
        // 네 카드의 높이를 같게 맞춘다 (각 카드는 내용 위에서 높이를 가득 채움)
        HStack(alignment: .top, spacing: 16) {
            ScopeCard(stats: stats, applied: state.appliedCount, duplicates: model.duplicateCompleteIDs(state.rows).count,
                      select: { model.showStatus($0) }, openApplied: { model.tab = .history },
                      showDuplicates: { model.showStatus(.complete); model.showDuplicatesOnly = true })
            MissingCard(stats: stats, selected: model.missingField) { model.showMissing($0) }
            identifyCard(stats)
            ApplyStatusCard { tab in model.tab = tab }
        }
        .frame(height: 236)
    }

    /// 식별 결과 (신뢰도별 막대). 적용을 마친 곡은 빠지므로 정리가 진행될수록 막대가 줄어든다.
    private func identifyCard(_ stats: ScanStats) -> some View {
        let applied = state.appliedProposalCounts
        let levels: [ConfidenceLevel] = [.high, .medium, .low, .none]
        let remaining = Dictionary(uniqueKeysWithValues: levels.map { ($0, (state.proposalCounts[$0] ?? 0) - (applied[$0] ?? 0)) })
        // 막대 높이 기준은 식별 직후의 가장 큰 막대 → 적용할수록 막대가 낮아지는 것이 보인다
        let scaleMax = max(1, levels.map { state.proposalCounts[$0] ?? 0 }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("dash.identifyResults")).font(.headline)
                Spacer()
                Text(Lf("count.songs", remaining.values.reduce(0, +))).font(.title3.bold()).monospacedDigit()
            }
            Chart(levels, id: \.self) { level in
                BarMark(x: .value("신뢰도", level.label), y: .value("곡 수", remaining[level] ?? 0), width: .ratio(0.55))
                    .foregroundStyle(color(for: level).gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(remaining[level] ?? 0)").font(.caption2).foregroundStyle(palette.secondaryText)
                    }
            }
            .chartYScale(domain: 0...Double(scaleMax) * 1.15)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(palette.secondaryText) }
            }
            .chartOverlay { proxy in
                GeometryReader { _ in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            if let label: String = proxy.value(atX: location.x),
                               let level = levels.first(where: { $0.label == label }) {
                                model.showProposals(level)
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: remaining)
        }
        .cardFill()
    }

    private func identify(force: Bool) async {
        await state.identify(force: force)
        model.tab = .proposals
    }

    // MARK: - 탭 내용

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.tab {
            case .review: ReviewQueueView()
            case .tracks: trackTable
            case .proposals: proposalTable
            case .history: HistoryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.secondaryText)
            TextField(L("dash.searchPlaceholder"), text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(palette.background))
        .frame(maxWidth: 260)
    }

    private var trackTable: some View {
        let rows = model.filteredRows(state.rows)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(DashboardViewModel.StatusFilter.allCases) { filter in
                    Button(filter.title) { model.showStatus(filter) }
                        .buttonStyle(PillButtonStyle(selected: model.status == filter && model.missingField == nil, compact: true))
                }
                if let field = model.missingField {
                    Button(Lf("dash.missingFilter", field.label)) { model.showMissing(field) }
                        .buttonStyle(PillButtonStyle(selected: true, compact: true))
                }
                if model.status == .complete {
                    Toggle(L("dash.duplicatesOnly"), isOn: $model.showDuplicatesOnly)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .padding(.leading, 8)
                        .help(L("dash.duplicatesOnly.help"))
                }
                Spacer()
                searchField
            }
            // 완비 목록은 '누락 항목' 대신 처리 상태(완비·검토 대기·적용 완료·적용 실패)를 보여 준다.
            // (조건부 TableColumn은 macOS 14.4+만 되므로 뷰 수준에서 테이블을 나눈다)
            if model.status == .complete {
                Table(rows, selection: $model.selection, sortOrder: $model.sortOrder) {
                    TableColumn(L("col.title"), value: \.title)
                    TableColumn(L("col.artist"), value: \.artist)
                    TableColumn(L("col.album"), value: \.album)
                    TableColumn(L("col.status"), value: \.processRank) { row in
                        Text(row.processStatusText).foregroundStyle(processColor(rank: row.processRank))
                    }
                    .width(min: 80, ideal: 110, max: 150)
                    TableColumn(L("col.file"), value: \.location)
                }
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: PersistentID.self) { ids in
                    if ids.count == 1, let id = ids.first { Button(L("common.directEditEllipsis")) { editing = EditTarget(id: id) } }
                } primaryAction: { ids in
                    if let id = ids.first { editing = EditTarget(id: id) }
                }
            } else {
                Table(rows, selection: $model.selection, sortOrder: $model.sortOrder) {
                    TableColumn(L("col.status"), value: \.statusText) { row in
                        Text(row.statusText)
                            .foregroundStyle(row.completeness == .incomplete ? palette.warning : palette.secondaryText)
                    }
                    .width(min: 60, ideal: 80, max: 110)
                    TableColumn(L("col.title"), value: \.title)
                    TableColumn(L("col.artist"), value: \.artist)
                    TableColumn(L("col.album"), value: \.album)
                    TableColumn(L("col.missing"), value: \.missingText)
                        .width(min: 90, ideal: 160)
                    TableColumn(L("col.file"), value: \.location)
                }
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: PersistentID.self) { ids in
                    if ids.count == 1, let id = ids.first { Button(L("common.directEditEllipsis")) { editing = EditTarget(id: id) } }
                } primaryAction: { ids in
                    if let id = ids.first { editing = EditTarget(id: id) }
                }
            }
            HStack(spacing: 10) {
                Text(Lf("dash.showingCount", rows.count))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button(L("common.directEdit")) {
                    if let id = model.selection.first { editing = EditTarget(id: id) }
                }
                .controlSize(.small)
                .disabled(model.selection.count != 1)
                .help(L("dash.directEdit.help"))
            }
        }
    }

    private var proposalTable: some View {
        let rows = model.filteredProposals(state.proposalRows)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(L("filter.all")) { model.proposalLevel = nil }
                    .buttonStyle(PillButtonStyle(selected: model.proposalLevel == nil, compact: true))
                ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                    Button("\(level.label) \(state.proposalCounts[level] ?? 0)") { model.proposalLevel = level }
                        .buttonStyle(PillButtonStyle(selected: model.proposalLevel == level, compact: true))
                }
                Toggle(L("dash.reviewOnly"), isOn: $model.reviewOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.leading, 8)
                    .help(L("dash.reviewOnly.help"))
                Spacer()
                searchField
            }
            Table(rows, selection: $model.proposalSelection, sortOrder: $model.proposalSortOrder) {
                TableColumn(L("col.confidence"), value: \.score) { row in
                    Text(row.levelText)
                        .foregroundStyle(color(for: row.level))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 80, max: 100)
                TableColumn(L("col.current"), value: \.current)
                TableColumn(L("col.propTitle"), value: \.title) { row in proposedCell(row.title, writes: row.writes.contains(.title)) }
                TableColumn(L("col.propArtist"), value: \.artist) { row in proposedCell(row.artist, writes: row.writes.contains(.artist)) }
                TableColumn(L("col.propAlbum"), value: \.album) { row in proposedCell(row.album, writes: row.writes.contains(.album)) }
                TableColumn(L("col.cover"), value: \.artwork) { row in proposedCell(row.artwork, writes: row.writes.contains(.artwork)) }
                    .width(min: 60, ideal: 100, max: 140)
                TableColumn(L("col.writes"), value: \.writesText) { row in
                    Text(row.writesText)
                        .foregroundStyle(row.writes.isEmpty ? palette.secondaryText : palette.text)
                        .help(row.writesText)
                }
                TableColumn(L("col.status"), value: \.decisionText) { row in
                    StatusCell(status: row.status) { editing = EditTarget(id: row.id) }
                }
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn(L("col.reasons"), value: \.reasons)
            }
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: PersistentID.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button(L("common.directEditEllipsis")) { editing = EditTarget(id: id) }
                }
                Button(L("dash.applySelected")) {
                    model.proposalSelection = ids
                    confirmApply = true
                }
                .disabled(ids.isEmpty)
            } primaryAction: { ids in
                // 더블클릭 → 직접 수정
                if let id = ids.first { editing = EditTarget(id: id) }
            }
            HStack {
                Text(Lf("dash.proposalFooter", rows.count))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Menu(L("dash.reviewSheet")) {
                    Button(L("dash.exportCSV")) { exportSheet() }
                    Button(L("dash.importCSV")) { importSheet() }
                }
                .fixedSize()
                .help(L("dash.reviewSheet.help"))
                Button(L("common.directEditEllipsis")) {
                    if let id = model.proposalSelection.first { editing = EditTarget(id: id) }
                }
                .disabled(model.proposalSelection.count != 1 || state.activity != nil)
                .help(L("dash.doubleClickHint"))
                Button(Lf("dash.applySelectedN", model.proposalSelection.count)) { confirmApply = true }
                    .disabled(model.proposalSelection.isEmpty || state.activity != nil)
                Button(Lf("dash.applyAllN", applicableRows(rows).count)) { confirmApplyAll = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(applicableRows(rows).isEmpty || state.activity != nil)
                    .help(L("dash.applyAll.help"))
            }
        }
        .alert(Lf("dash.confirmApplyAll.title", applicableRows(rows).count), isPresented: $confirmApplyAll) {
            Button(L("dash.applyAllConfirm")) {
                let ids = Set(applicableRows(rows).map(\.id))
                Task { await state.apply(ids) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(Lf("dash.confirmApplyAll.msgFiltered", model.proposalLevel.map { Lf("dash.confirmApplyAll.filterPrefix", $0.label) } ?? ""))
        }
        .alert(Lf("dash.confirmApply.title", model.proposalSelection.count), isPresented: $confirmApply) {
            Button(L("common.apply")) {
                let ids = model.proposalSelection
                Task { await state.apply(ids) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("dash.confirmApply.msg"))
        }
    }

    private func exportSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = Lf("dash.exportFilename", Date().formatted(.iso8601.year().month().day()))
        if panel.runModal() == .OK, let url = panel.url { state.exportReviewSheet(to: url) }
    }

    private func importSheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        if panel.runModal() == .OK, let url = panel.url { importResult = state.importReviewSheet(from: url) }
    }

    private func applicableRows(_ rows: [ProposalRow]) -> [ProposalRow] {
        rows.filter(\.isApplicable)
    }

    /// 실제로 쓸 값은 그대로, 쓰지 않는 참고 값은 흐리게 '참고'로 표시
    @ViewBuilder
    private func proposedCell(_ value: String, writes: Bool) -> some View {
        if value.isEmpty {
            Text("")
        } else if writes {
            Text(value).fontWeight(.medium)
        } else {
            Text(Lf("dash.referenceValue", value))
                .foregroundStyle(palette.secondaryText)
                .help(L("dash.reference.help"))
        }
    }

    private func color(for level: ConfidenceLevel) -> Color {
        switch level {
        case .high: return palette.accent
        case .medium: return palette.accentBlue
        case .low: return palette.warning
        case .none: return palette.accentSlate
        }
    }

    /// 완비 목록 '상태' 열의 색 (처리 순위 기준: 3 적용 완료 · 2 적용 실패 · 1 검토 대기)
    private func processColor(rank: Int) -> Color {
        switch rank {
        case 3: return palette.success
        case 2: return palette.danger
        case 1: return palette.warning
        default: return palette.secondaryText
        }
    }
}

// MARK: - 카드들

/// 대상 곡 (남색 강조 카드 + 완비율 링). 적용 결과가 바로 반영된 현황이다.
private struct ScopeCard: View {
    @Environment(\.palette) private var palette
    let stats: ScanStats
    /// 앱에서 수정을 마친 곡 수
    let applied: Int
    /// 완비 목록의 중복곡(제목·가수 같은 곡) 수
    let duplicates: Int
    let select: (DashboardViewModel.StatusFilter) -> Void
    let openApplied: () -> Void
    let showDuplicates: () -> Void

    private var completeRatio: Double {
        stats.scopeTotal == 0 ? 0 : Double(stats.complete) / Double(stats.scopeTotal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("card.scope.title")).font(.headline).opacity(0.9)
                    Text(stats.scopeTotal, format: .number)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                    Circle().trim(from: 0, to: completeRatio)
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((completeRatio * 100).rounded()))%").font(.callout.bold())
                        Text(L("card.complete.ring")).font(.system(size: 9)).opacity(0.7)
                    }
                }
                .frame(width: 58, height: 58)
            }
            Spacer(minLength: 0)
            row(L("completeness.complete"), stats.complete, accent: false) { select(.complete) }
            if duplicates > 0 {
                row(L("card.duplicateTracks"), duplicates, color: palette.accentBlue) { showDuplicates() }
                    .help(L("dash.duplicatesOnly.help"))
            }
            row(L("completeness.incomplete"), stats.incomplete, accent: true) { select(.incomplete) }
            row(L("card.applied"), applied, color: palette.success) { openApplied() }
                .help(L("card.applied.help"))
            row(L("filter.excluded"), stats.excludedTotal, accent: false) { select(.excluded) }
        }
        .cardFill(strong: true)
    }

    private func row(_ title: String, _ value: Int, accent: Bool = false, color: Color? = nil, action: @escaping () -> Void) -> some View {
        let tint = color ?? (accent ? palette.accent : nil)
        return Button(action: action) {
            HStack {
                Circle().fill(tint ?? Color.white.opacity(0.5)).frame(width: 6, height: 6)
                Text(title).font(.callout).opacity(0.85)
                Spacer()
                Text(value, format: .number).font(.callout.bold()).monospacedDigit()
                    .foregroundStyle(tint ?? .white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 누락 항목 도넛
private struct MissingCard: View {
    @Environment(\.palette) private var palette
    let stats: ScanStats
    let selected: RequiredField?
    let select: (RequiredField) -> Void

    private var colors: [RequiredField: Color] {
        [.artwork: palette.accent, .title: palette.accentBlue, .artist: palette.accentSlate, .album: palette.accentDeep]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("card.missing.title")).font(.headline)
            HStack(spacing: 12) {
                ZStack {
                    Chart(RequiredField.allCases, id: \.self) { field in
                        SectorMark(angle: .value("곡 수", stats.missingCounts[field] ?? 0), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .foregroundStyle(colors[field] ?? palette.accent)
                            .cornerRadius(3)
                            .opacity(selected == nil || selected == field ? 1 : 0.35)
                    }
                    VStack(spacing: 0) {
                        Text(stats.incomplete, format: .number).font(.headline).monospacedDigit()
                        Text(L("completeness.incomplete")).font(.system(size: 9)).foregroundStyle(palette.secondaryText)
                    }
                }
                .frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(RequiredField.allCases, id: \.self) { field in
                        let count = stats.missingCounts[field] ?? 0
                        Button {
                            select(field)
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(colors[field] ?? palette.accent).frame(width: 8, height: 8)
                                Text(field.label).font(.callout)
                                    .lineLimit(1)
                                    .fixedSize()
                                Spacer(minLength: 6)
                                Text(count, format: .number).font(.callout.bold()).monospacedDigit()
                                    .fixedSize()
                            }
                            .foregroundStyle(selected == field ? palette.accent : palette.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .cardFill()
    }
}

/// 적용 현황 (가로 막대)
private struct ApplyStatusCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    let open: (DashboardViewModel.Tab) -> Void

    var body: some View {
        let rows = state.proposalRows
        let failed = rows.filter { if case .failed = $0.status { return true } else { return false } }.count
        let unidentified = state.unidentifiedCount
        // 분모는 스캔한 전체 곡 수로 둔다. 수정 완료(appliedCount)는 적용 누적분이라
        // 제안 행 수(rows)보다 커질 수 있어, rows.count를 쓰면 막대가 컨테이너 밖으로 넘쳐 깨진다.
        let total = max(1, state.rows.count, state.appliedCount + state.reviewCount + failed + unidentified)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L("card.applyStatus.title")).font(.headline)
                Spacer(minLength: 4)
                Button(L("tab.review")) { open(.review) }
                    .buttonStyle(PillButtonStyle(selected: false, compact: true))
                Button(L("tab.history")) { open(.history) }
                    .buttonStyle(PillButtonStyle(selected: false, compact: true))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                bar(L("card.bar.applied"), state.appliedCount, total, palette.success)
                bar(L("card.bar.pending"), state.reviewCount, total, palette.warning)
                bar(L("card.bar.failed"), failed, total, palette.danger)
                bar(L("card.bar.unidentified"), unidentified, total, palette.accentSlate)
            }
            Spacer(minLength: 0)
        }
        .cardFill()
    }

    private func bar(_ title: String, _ value: Int, _ total: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(value, format: .number).font(.callout.bold()).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(color.gradient)
                        .frame(width: min(geometry.size.width,
                                          max(value > 0 ? 6 : 0, geometry.size.width * CGFloat(value) / CGFloat(total))))
                }
            }
            .frame(height: 6)
        }
    }
}

/// 식별 실행 (강조색 버튼 + 다시 식별 메뉴)
private struct IdentifyButton: View {
    @Environment(\.palette) private var palette
    let disabled: Bool
    let run: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                run(false)
            } label: {
                Label(L("dash.runIdentify"), systemImage: "waveform.and.magnifyingglass")
                    .font(.body.weight(.semibold))
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("dash.runIdentify.help"))
            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 18)
            Menu {
                Button(L("dash.reidentifyAll")) { run(true) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
        }
        .foregroundStyle(.white)
        .background {
            Capsule().fill(LinearGradient(colors: [Color(hex: 0x7C5CFF), Color(hex: 0xC04DFF)],
                                          startPoint: .leading, endPoint: .trailing))
        }
        .shadow(color: Color(hex: 0x9B5CFF).opacity(hovering && !disabled ? 0.55 : 0.3), radius: hovering ? 10 : 6)
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .keyboardShortcut("i")
        .fixedSize()
    }
}

/// 진행 중인 작업 한 줄 (단계가 바뀌면 그 단계 기준으로 다시 센다)
private struct ActivityBar: View {
    @Environment(\.palette) private var palette
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(activity.title).font(.callout.weight(.semibold))
            if let fraction = activity.fraction {
                ProgressView(value: fraction)
                    .tint(palette.accent)
                    .frame(maxWidth: 360)
                Text(activity.countText).font(.callout).monospacedDigit().foregroundStyle(palette.secondaryText)
            } else {
                ProgressView().progressViewStyle(.linear).tint(palette.accent).frame(maxWidth: 360)
            }
            Text(activity.detail).font(.callout).foregroundStyle(palette.secondaryText).lineLimit(1)
            Spacer()
        }
        .card(padding: 10)
    }
}

/// 상태 텍스트 (상태별 색). 사유가 있으면 눌러서 볼 수 있다.
private struct StatusCell: View {
    @Environment(\.palette) private var palette
    let status: ProposalRow.RowStatus
    var edit: (() -> Void)?
    @State private var showDetail = false

    var body: some View {
        if let detail = status.detail {
            Button {
                showDetail = true
            } label: {
                HStack(spacing: 3) {
                    Text(status.text)
                    Image(systemName: "info.circle").font(.caption)
                }
                .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .help(detail)
            .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.text).font(.headline).foregroundStyle(color)
                    Text(detail).fixedSize(horizontal: false, vertical: true)
                    if case .failed = status {
                        Divider()
                        Text(L("dash.failed.hint"))
                            .font(.caption).foregroundStyle(.secondary)
                        if let edit {
                            Button(L("dash.editToApply")) {
                                showDetail = false
                                edit()
                            }
                        }
                    }
                    if case .unidentified = status, let edit {
                        Divider()
                        Text(L("dash.unidentified.hint"))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(L("dash.enterToReidentify")) {
                            showDetail = false
                            edit()
                        }
                    }
                }
                .padding(14)
                .frame(width: 320)
            }
        } else {
            Text(status.text).foregroundStyle(color)
        }
    }

    private var color: Color {
        switch status {
        case .applied: return palette.success
        case .failed: return palette.danger
        case .pending: return palette.warning
        case .override: return palette.accentBlue
        case .unidentified, .nothingToChange, .rejected: return palette.secondaryText
        }
    }
}

/// 대시보드·설정에서 쓰는 플레이리스트 변경 시트
struct PlaylistSelectionSheet: View {
    @Environment(AppState.self) private var state
    @Bindable var model: PlaylistPickerViewModel
    let dismiss: () -> Void
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("sheet.scopePlaylists")).font(.title2.bold())
            PlaylistPickerView(model: model)
            HStack {
                Spacer()
                Button(L("common.cancel"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NeutralActionButtonStyle())
                Button(L("common.apply")) {
                    if state.hasHistory { confirmReset = true } else { apply() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasSelection || !model.isDirty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .task { await model.load() }
        .alert(L("settings.playlist.confirmTitle"), isPresented: $confirmReset) {
            Button(L("settings.playlist.confirmChange"), role: .destructive) { apply() }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(PlaylistSelectionSheet.resetMessage)
        }
    }

    static var resetMessage: String { L("sheet.resetMessage") }

    private func apply() {
        Task {
            await model.apply()
            dismiss()
        }
    }
}

extension PlaylistPickerViewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

