import AppKit
import MTMCore
import SwiftUI
import UniformTypeIdentifiers

/// 식별 실패·낮음 등의 제안을 사용자가 직접 고쳐 적용한다 (입력한 값은 기존 값과 달라도 쓴다)
struct ProposalEditView: View {
    @Environment(AppState.self) private var state
    let id: PersistentID
    let dismiss: () -> Void
    @State private var values = EditableValues()
    /// 처음 불러온 값 (변경 여부 판정 기준)
    @State private var baseline = EditableValues()
    @State private var artworkFile: URL?
    @State private var artworkPreview: NSImage?
    @State private var isDropTargeted = false
    @State private var isSaving = false
    @State private var isReidentifying = false
    /// 입력한 정보로 다시 식별한 결과
    @State private var reidentified: ProposalRow?
    @State private var reidentifyFailed = false
    /// 다시 식별로 찾은 앨범커버 (이미지 영역에 미리 보여 준다)
    @State private var reidentifiedArtwork: NSImage?
    /// 이미 곡에 저장되어 있는 앨범커버 (아무 것도 고르지 않았을 때 기본으로 보여 준다)
    @State private var existingArtwork: NSImage?
    /// 앨범커버 검색 상태
    @State private var isSearchingCovers = false
    @State private var coverCandidates: [AlbumCoverCandidate] = []
    @State private var showCoverPicker = false
    @State private var showNoCoversAlert = false
    /// 곡 미리 듣기 재생기 (팝업이 소유하고, 닫힐 때 멈춘다)
    @State private var preview = AudioPreviewPlayer()
    @State private var showNoAudioAlert = false

    var body: some View {
        // 3단 고정 레이아웃: 헤더(상단 고정) · 콘텐츠(남는 공간을 채우며 상단 정렬) · 액션(하단 고정).
        // 루트를 하나의 VStack으로 두고 고정 높이를 주면, 콘텐츠가 프레임보다 짧을 때 전체가 세로 중앙으로
        // 정렬되어 내용이 늘거나 줄 때마다 헤더·버튼이 위아래로 움직인다. 아래처럼 콘텐츠 영역에만
        // maxHeight: .infinity + 상단 정렬을 줘서, 남는 여백은 항상 콘텐츠 아래(버튼 위)에만 생기게 한다.
        VStack(alignment: .leading, spacing: 0) {
            // 상단 헤더 (고정). 제목+현재 곡 정보 블록 오른쪽에 큰 미리 듣기 버튼을 세로 중앙으로 둔다.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("common.directEdit")).font(.title2.bold())
                    // 곡 정보는 1줄로 고정, 영역보다 길면 말줄임(…) 처리 → 세로 길이가 늘지 않음
                    Text(Lf("edit.currentPrefix", values.currentSummary))
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                previewButton
            }

            // 중앙 콘텐츠 (상단 정렬, 남는 세로 공간을 모두 차지 → 내용이 줄어도 중앙으로 몰리지 않음)
            VStack(alignment: .leading, spacing: 14) {
                // 섹션 간격을 직접 제어하려고 grouped Form 대신 커스텀 카드로 구성 (섹션 사이 14pt)
                VStack(spacing: 14) {
                    editSection(L("edit.section.songInfo")) {
                        editRow(L("field.title"), text: $values.title)
                        Divider()
                        editRow(L("field.artist"), text: $values.artist)
                        Divider()
                        editRow(L("field.album"), text: $values.album)
                        Divider()
                        editRow(L("field.albumArtist"), text: $values.albumArtist)
                        Divider()
                        editRow(L("field.genre"), text: $values.genre)
                    }
                    editSection(L("edit.section.numbers")) {
                        HStack(spacing: 20) {
                            editRow(L("field.year"), text: $values.year)
                            editRow(L("field.trackNumber"), text: $values.trackNumber)
                            editRow(L("field.trackCount"), text: $values.trackCount)
                        }
                        Divider()
                        HStack(spacing: 20) {
                            editRow(L("field.discNumber"), text: $values.discNumber)
                            editRow(L("field.discCount"), text: $values.discCount)
                        }
                    }
                    editSection(L("field.artwork")) { artworkSection }
                }

                if !values.invalidNumbers.isEmpty {
                    // 세로 공간 절약을 위해 한 줄로 고정 (넘치면 끝을 … 로 줄임)
                    Label(Lf("edit.invalidNumbers", values.invalidNumbers.joined(separator: ", ")), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.callout)
                        .lineLimit(1).truncationMode(.tail)
                }

                // 로딩·식별 결과·식별 실패 이유는 앨범커버 영역 아래(같은 영역)에 표시한다.
                // 이 조건부 영역이 나타나거나 사라져도 상단 섹션·하단 버튼은 움직이지 않는다 (여백은 이 아래에서 흡수).
                if isReidentifying {
                    reidentifyingStatus
                } else if let reidentified {
                    reidentifyResult(reidentified)
                } else if let row = currentRow, row.isUnidentified, let reason = row.status.detail {
                    failReasonBox(reason)
                }
                if reidentifyFailed, !isReidentifying {
                    Label(state.errorMessage ?? L("edit.reidentifyFailed"), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 하단 액션 (고정)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("edit.writeNote"))
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button {
                        reidentify()
                    } label: {
                        if isReidentifying {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("edit.identifying")) }
                        } else {
                            Label(L("edit.reidentifyButton"), systemImage: "waveform.and.magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x7C5CFF))
                    .disabled(isReidentifying || isSaving || state.activity != nil
                              || (values.title.trimmingCharacters(in: .whitespaces).isEmpty && values.artist.trimmingCharacters(in: .whitespaces).isEmpty))
                    .help(L("edit.reidentify.help"))
                    Spacer()
                    Button(L("common.cancel"), action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(NeutralActionButtonStyle())
                    Button(L("edit.save")) { save(applyNow: false) }
                        .disabled(!values.invalidNumbers.isEmpty || isSaving || !hasChanges)
                        .buttonStyle(NeutralActionButtonStyle())
                    Button(L("edit.saveApply")) { save(applyNow: true) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!values.invalidNumbers.isEmpty || isSaving || state.isApplying || !hasChanges)
                }
            }
            .padding(.top, 12)
        }
        .padding(20)
        // 높이 고정: 콘텐츠 상태가 바뀌어도 팝업 크기는 그대로. 곡 정보 1줄 고정 + '선택 취소' 오른쪽 이동으로
        // 가장 긴 상태가 줄어 770으로 축소. (모든 섹션 + 재식별 결과/실패 사유 박스 + 안내문 + 버튼이 들어감)
        .frame(width: 580, height: 770)
        .onAppear {
            let loaded = state.editableValues(for: id)
            values = loaded
            baseline = loaded
            // 이미 저장된 커버가 있으면 이미지 영역에 기본으로 보여 준다
            if loaded.hasArtwork {
                Task { existingArtwork = await state.artworkImage(for: "track:\(id.hex)") }
            }
        }
        .onDisappear { preview.stop() }
        .sheet(isPresented: $showCoverPicker) {
            CoverPickerSheet(candidates: coverCandidates, select: chooseCover, cancel: { showCoverPicker = false })
        }
        .alert(L("edit.noCoversTitle"), isPresented: $showNoCoversAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(L("edit.noCoversMsg"))
        }
        .alert(L("edit.preview.unavailableTitle"), isPresented: $showNoAudioAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(L("edit.preview.unavailableMsg"))
        }
    }

    /// 미리 듣기 버튼: 재생 중이면 일시정지 아이콘으로 바뀐다. 재생할 파일이 없으면 안내 알림을 띄운다.
    private var isPreviewingThisTrack: Bool { preview.currentID == id && preview.isPlaying }

    private var previewButton: some View {
        Button {
            togglePreview()
        } label: {
            Image(systemName: isPreviewingThisTrack ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color(hex: 0x7C5CFF), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(isPreviewingThisTrack ? L("edit.preview.pause") : L("edit.preview.play"))
        .accessibilityLabel(isPreviewingThisTrack ? L("edit.preview.pause") : L("edit.preview.play"))
    }

    private func togglePreview() {
        // 이미 이 곡이 로드돼 있으면 일시정지/재개만 토글
        if preview.currentID == id {
            preview.toggle()
            return
        }
        guard let url = state.previewAudioURL(for: id), preview.play(id: id, url: url) else {
            showNoAudioAlert = true
            return
        }
    }

    private var currentRow: ProposalRow? { state.proposalRows.first { $0.id == id } }

    /// 저장할 변경이 있는가: 입력값이 처음 값과 다르거나, 커버 파일을 새로 골랐을 때
    private var hasChanges: Bool { values != baseline || artworkFile != nil }

    /// 제목 있는 카드 섹션 (grouped Form보다 간격을 좁게 직접 제어)
    @ViewBuilder
    private func editSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 8) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// 라벨(왼쪽) + 값 입력(오른쪽 정렬) 한 줄
    private func editRow(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
        }
    }

    /// 식별 실패 이유 (식별 결과가 표시되는 하단 영역과 같은 자리)
    private func failReasonBox(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("edit.failReasonTitle")).font(.callout.weight(.semibold))
            Text(reason).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 다시 식별이 진행되는 동안 결과 영역에 스피너를 보여 준다
    private var reidentifyingStatus: some View {
        HStack {
            Text(L("edit.reidentifying")).font(.callout.weight(.semibold))
            Spacer()
            ProgressView().controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 다시 식별한 결과: 찾았으면 제안값과 바로 적용 버튼, 못 찾았으면 이유
    private func reidentifyResult(_ row: ProposalRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.isUnidentified ? L("edit.reResultNotFound") : Lf("edit.reResult", row.levelText))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(row.isUnidentified ? Color.secondary : Color.green)
                Spacer()
                if !row.isUnidentified {
                    Button(L("edit.applyResult")) {
                        Task {
                            await state.apply([id])
                            dismiss()
                        }
                    }
                    .disabled(!row.isApplicable || state.isApplying)
                    .help(row.isApplicable ? Lf("edit.applyResult.help", row.writesText) : row.writesText)
                }
            }
            if row.isUnidentified {
                Text(row.status.detail ?? "").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text([row.title, row.artist, row.album].map { $0.isEmpty ? "∅" : $0 }.joined(separator: " · ")
                     + (row.artwork.isEmpty ? "" : Lf("edit.coverSuffix", row.artwork)))
                    .font(.callout)
                Text(L("edit.filledNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func reidentify() {
        isReidentifying = true
        reidentifyFailed = false
        Task {
            let row = await state.reidentify(id, title: values.title, artist: values.artist, album: values.album)
            guard let row else {
                reidentifyFailed = true
                isReidentifying = false
                return
            }
            reidentified = row
            if !row.isUnidentified {
                // 찾은 값을 입력 칸에 채운다 (사용자가 고르지 않은 커버 파일은 유지)
                values = state.editableValues(for: id)
                // 찾은 앨범커버를 이미지 영역에도 미리 보여 준다
                if let ref = row.artworkRef {
                    reidentifiedArtwork = await state.artworkImage(for: ref)
                }
            }
            isReidentifying = false
        }
    }

    private var artworkSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                if let shownArtwork = artworkPreview ?? reidentifiedArtwork ?? existingArtwork {
                    Image(nsImage: shownArtwork).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(L("art.dropHere")).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .onDrop(of: ImageDrop.types, isTargeted: $isDropTargeted) { providers in
                Task { if let url = await ImageDrop.load(providers) { choose(url) } }
                return true
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(currentArtworkText).font(.callout)
                Button {
                    searchCovers()
                } label: {
                    if isSearchingCovers {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("edit.coverSearching")) }
                    } else {
                        Label(L("edit.coverSearch"), systemImage: "photo.on.rectangle.angled")
                    }
                }
                .disabled(isSearchingCovers || !hasCoverSearchTerm)
                .help(L("edit.coverSearch.help"))
                Button(L("edit.pickFile")) { pickFile() }
                Button(L("edit.pasteClipboard")) {
                    if let url = ImageDrop.fromPasteboard() { choose(url) }
                }
            }
            Spacer()
            // '선택 취소'는 세로로 줄을 늘리지 않도록 오른쪽 영역에 둔다 (커버를 고른 경우에만)
            if artworkFile != nil {
                Button(L("edit.clearSelection")) {
                    artworkFile = nil
                    artworkPreview = nil
                }
                .buttonStyle(.link)
            }
        }
    }

    /// 검색어로 쓸 값(제목·가수·앨범)이 하나라도 입력되어 있는지
    private var hasCoverSearchTerm: Bool {
        [values.title, values.artist, values.album].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func searchCovers() {
        isSearchingCovers = true
        Task {
            let results = await state.searchAlbumCovers(title: values.title, artist: values.artist, album: values.album)
            isSearchingCovers = false
            coverCandidates = results
            if results.isEmpty {
                showNoCoversAlert = true
            } else {
                showCoverPicker = true
            }
        }
    }

    /// 고른 커버를 내려받아 이미지 영역에 넣는다 (저장 시 실제 파일에 기록됨)
    private func chooseCover(_ candidate: AlbumCoverCandidate) {
        showCoverPicker = false
        isSearchingCovers = true
        Task {
            if let url = await state.downloadCover(candidate), let image = NSImage(contentsOf: url) {
                artworkFile = url
                artworkPreview = image
                reidentifiedArtwork = nil
            } else {
                showNoCoversAlert = true
            }
            isSearchingCovers = false
        }
    }

    private var currentArtworkText: String {
        if artworkFile != nil { return values.hasArtwork ? L("edit.art.replaceWithSelected") : L("edit.art.useSelected") }
        if values.hasArtwork { return L("edit.art.keepExisting") }
        if let proposed = values.proposedArtwork { return Lf("edit.art.useProposed", proposed) }
        return L("edit.art.none")
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    private func choose(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        artworkFile = url
        artworkPreview = image
    }

    private func save(applyNow: Bool) {
        isSaving = true
        Task {
            await state.saveOverride(for: id, values: values, artworkFile: artworkFile, applyNow: applyNow)
            isSaving = false
            dismiss()
        }
    }
}

/// 검색된 앨범커버 후보를 격자로 보여 주고 하나를 고르게 한다
private struct CoverPickerSheet: View {
    let candidates: [AlbumCoverCandidate]
    let select: (AlbumCoverCandidate) -> Void
    let cancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("edit.coverPicker.title")).font(.title3.bold())
            Text(Lf("edit.coverPicker.desc", candidates.count))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(candidates) { candidate in
                        Button { select(candidate) } label: {
                            VStack(spacing: 4) {
                                AsyncImage(url: candidate.thumbnailURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    ZStack { Color.secondary.opacity(0.1); ProgressView().controlSize(.small) }
                                }
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(candidate.albumTitle.isEmpty ? candidate.artist : candidate.albumTitle)
                                    .font(.caption).lineLimit(1).truncationMode(.middle)
                                Text(candidate.source == .itunes ? "iTunes" : "Deezer")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button(L("common.cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NeutralActionButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }
}
