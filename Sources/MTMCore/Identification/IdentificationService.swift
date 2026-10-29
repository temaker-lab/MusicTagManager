import Foundation

/// 앨범 검색·조회 공통 인터페이스. 소스를 추가하거나 바꿀 때 이 형태를 따른다.
public protocol MetadataProvider: Sendable {
    var providerID: ProviderID { get }
    func searchAlbums(title: String, artist: String?) async throws -> [ReleaseCandidate]
    func album(id: String) async throws -> ReleaseCandidate
}

extension MusicBrainzProvider: MetadataProvider {
    public var providerID: ProviderID { .musicbrainz }

    public func searchAlbums(title: String, artist: String?) async throws -> [ReleaseCandidate] {
        var artistID: String?
        if let artist { artistID = try await resolveArtist(named: artist)?.id }
        return try await searchReleases(title: title, artistID: artistID)
    }

    public func album(id: String) async throws -> ReleaseCandidate {
        try await release(id: id)
    }
}

extension ITunesSearchProvider: MetadataProvider {
    public var providerID: ProviderID { .itunes }

    public func searchAlbums(title: String, artist: String?) async throws -> [ReleaseCandidate] {
        try await searchAlbums(term: [artist, title].compactMap { $0 }.joined(separator: " "))
    }
}

public struct IdentificationProgress: Sendable {
    /// 처리한 곡 수 (식별은 앨범 그룹 단위로 돌지만, 진행 표시는 곡 수로 보여 준다)
    public var completedTracks: Int
    public var totalTracks: Int
    /// 지금 처리 중인 곡 제목
    public var currentLabel: String
}

public struct IdentificationSummary: Sendable, Equatable {
    public var groups = 0
    public var tracks = 0
    public var levels: [ConfidenceLevel: Int] = [:]
    public var skipped = 0
    public var errors = 0
    public var duration: TimeInterval = 0
}

/// 정리 대상 곡을 앨범 그룹으로 묶어 식별하고 제안값을 저장한다. Music 보관함은 수정하지 않는다.
public final class IdentificationService: Sendable {
    private let database: AppDatabase
    private let resolver: AlbumResolver
    private let settings: IdentificationSettings
    private let concurrency: Int

    public init(database: AppDatabase, musicBrainz: MusicBrainzProvider, itunes: ITunesSearchProvider?,
                acoustID: AcoustIDProvider?, settings: IdentificationSettings = IdentificationSettings(), concurrency: Int = 3) {
        self.database = database
        self.settings = settings
        self.concurrency = concurrency
        resolver = AlbumResolver(musicBrainz: musicBrainz,
                                 itunes: settings.useITunes ? itunes : nil,
                                 acoustID: settings.useAcoustID ? acoustID : nil,
                                 scorer: ConfidenceScorer(weights: settings.weights))
    }

    /// - Parameters:
    ///   - scope: 마지막 스캔의 범위 내 곡 전체 (완비 곡은 같은 앨범의 참고 근거로만 쓴다)
    ///   - force: 이미 식별한 곡도 다시 식별
    ///   - maxGroups: 처리할 그룹 수 제한 (점검용)
    public func identify(scope: [EvaluatedTrack], force: Bool = false, maxGroups: Int? = nil,
                         progress: @escaping @Sendable (IdentificationProgress) -> Void = { _ in }) async throws -> IdentificationSummary {
        let started = Date()
        let eligible = scope.filter { $0.result.completeness.isEligible }
        try database.pruneProposals(keeping: Set(eligible.map(\.id.hex)))
        let states = try database.proposalStates()
        let needsWork = Set(eligible.filter { force || Self.needsIdentification(states[$0.id], $0) }.map(\.id))
        var groups = Self.makeGroups(scope: scope).filter { group in group.targets.contains { needsWork.contains($0.id) } }
        if let maxGroups { groups = Array(groups.prefix(maxGroups)) }

        var summary = IdentificationSummary()
        summary.groups = groups.count
        let totalTracks = groups.reduce(0) { $0 + $1.targets.count }
        progress(IdentificationProgress(completedTracks: 0, totalTracks: totalTracks, currentLabel: ""))
        let builder = ProposalBuilder(settings: settings)
        func save(_ group: IdentificationGroup, _ resolution: GroupResolution) throws {
            let (album, proposals) = builder.build(group: group, resolution: resolution)
            try database.saveIdentification(album: album, albumGroupKey: group.key, proposals: proposals)
            summary.tracks += proposals.count
            for proposal in proposals {
                summary.levels[proposal.confidenceLevel, default: 0] += 1
                if proposal.decision == .skipped { summary.skipped += 1 }
                if proposal.evidence.error != nil { summary.errors += 1 }
            }
        }

        // 앨범 그룹은 끝나는 대로 저장하고, 단독 곡은 모두 끝난 뒤 같은 앨범끼리 정리해서 저장한다
        var singles: [(IdentificationGroup, GroupResolution)] = []
        try await withThrowingTaskGroup(of: (IdentificationGroup, GroupResolution).self) { taskGroup in
            var iterator = groups.makeIterator()
            func enqueue() {
                guard let group = iterator.next() else { return }
                taskGroup.addTask { [resolver] in
                    do {
                        return (group, try await resolver.resolve(group))
                    } catch let error as HTTPError where error == .offline {
                        throw error
                    } catch {
                        Log.identify.error("그룹 식별 실패 \(group.key, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (group, GroupResolution(error: error.localizedDescription))
                    }
                }
            }
            for _ in 0..<concurrency { enqueue() }
            var completedTracks = 0
            while let (group, resolution) = try await taskGroup.next() {
                // 일시정지: 끝난 그룹까지만 저장하고 멈춘다 (다음 실행 때 남은 곡부터)
                if Task.isCancelled {
                    taskGroup.cancelAll()
                    throw CancellationError()
                }
                completedTracks += group.targets.count
                if group.isSingle {
                    singles.append((group, resolution))
                } else {
                    try save(group, resolution)
                }
                let label = group.targets.first.map { Normalizer.clean($0.track.title).isEmpty ? Normalizer.clean($0.track.album) : Normalizer.clean($0.track.title) } ?? ""
                progress(IdentificationProgress(completedTracks: completedTracks, totalTracks: totalTracks, currentLabel: label))
                enqueue()
            }
        }
        for (group, resolution) in resolver.consolidateSingles(singles) {
            try save(group, resolution)
        }
        summary.duration = Date().timeIntervalSince(started)
        Log.identify.info("식별 완료: 그룹 \(summary.groups), 곡 \(summary.tracks), \(summary.duration, format: .fixed(precision: 1))s")
        return summary
    }

    /// 사용자가 입력한 제목·가수·앨범을 단서로 곡 하나만 다시 식별한다. Music 보관함은 수정하지 않는다.
    /// 입력한 값은 검색에만 쓰고, 제안의 기준(비어 있던 항목·수정 시각·바뀔 값)은 실제 곡 값으로 저장한다.
    @discardableResult
    public func identifyWithHints(_ evaluated: EvaluatedTrack, title: String?, artist: String?, album: String?) async throws -> ProposalRecord {
        func clean(_ value: String?) -> String? {
            let cleaned = Normalizer.clean(value)
            return cleaned.isEmpty ? nil : cleaned
        }
        // 비어 있던 항목에 지금 값(예: Unknown Album 같은 자리표시 값)이 그대로 들어왔으면 단서가 아니다
        func hint(_ value: String?, _ field: RequiredField, current: String?) -> String? {
            guard let value = clean(value) else { return nil }
            if evaluated.result.missing.contains(field), Normalizer.compareKey(value) == Normalizer.compareKey(current) { return nil }
            return value
        }
        let title = hint(title, .title, current: evaluated.track.title)
        let artist = hint(artist, .artist, current: evaluated.track.artist)
        let album = hint(album, .album, current: evaluated.track.album)
        var hinted = evaluated.track
        if let title { hinted.title = title }
        if let artist { hinted.artist = artist }
        if let album { hinted.album = album }
        // 입력한 항목은 '기존 값'으로 보고 검색·비교에 쓴다
        let entered: Set<RequiredField> = Set([title.map { _ in .title }, artist.map { _ in .artist }, album.map { _ in .album }].compactMap { $0 })
        let hintedResult = CompletenessResult(evaluated.result.completeness, missing: evaluated.result.missing.filter { !entered.contains($0) })
        let target = EvaluatedTrack(track: hinted, result: hintedResult)

        let resolved: GroupResolution
        do {
            resolved = try await resolver.resolveSingle(LocalView(target))
        } catch let error as HTTPError where error == .offline {
            throw error
        } catch {
            resolved = GroupResolution(error: error.localizedDescription)
        }
        // 사용자가 고른 단서로 찾은 앨범을 그대로 제안한다 (앨범명도 그 앨범으로 바뀌므로 커버·트랙 번호도 그 앨범 것)
        var resolution = resolved
        for id in Array(resolution.outcomes.keys) { resolution.outcomes[id]?.matchedAsAlbum = true }
        let groupKey = TrackRecord.albumGroupKey(for: evaluated.track, missing: evaluated.result.missing)
        let builder = ProposalBuilder(settings: settings)
        let (_, proposals) = builder.build(group: IdentificationGroup(key: groupKey, targets: [target], references: []), resolution: resolution)
        guard var record = proposals.first else { throw CancellationError() }
        record.missingAtIdentification = evaluated.result.missing
        record.trackModifiedAt = evaluated.track.modifiedDate?.timeIntervalSince1970
        record.fieldStatus = builder.fieldStatus(record, current: evaluated.track)
        record.evidence.reasons.insert("입력한 정보로 다시 식별", at: 0)
        try database.saveHintedIdentification(record)
        return record
    }

    /// 아직 식별하지 않았거나, 식별 후 곡이 바뀌었거나, 비어 있는 항목이 달라졌거나, 지난번에 실패한 곡
    static func needsIdentification(_ state: AppDatabase.ProposalState?, _ evaluated: EvaluatedTrack) -> Bool {
        guard let state else { return true }
        if state.level == .none { return true }
        if state.missing != evaluated.result.missing { return true }
        return state.trackModifiedAt != evaluated.track.modifiedDate?.timeIntervalSince1970
    }

    /// 같은 (앨범 아티스트, 앨범)으로 묶는다. 앨범명이 없는 곡은 단독 그룹.
    /// 가수명이 비어 같은 앨범이 둘로 갈라지면, 앨범명이 같은 그룹이 하나뿐일 때 합친다.
    static func makeGroups(scope: [EvaluatedTrack]) -> [IdentificationGroup] {
        var targets: [String: [EvaluatedTrack]] = [:]
        var references: [String: [EvaluatedTrack]] = [:]
        var order: [String] = []
        for evaluated in scope where evaluated.result.completeness == .incomplete || evaluated.result.completeness == .complete {
            var key = TrackRecord.albumGroupKey(for: evaluated.track, missing: evaluated.result.missing)
            if evaluated.result.completeness == .incomplete {
                if targets[key] == nil { order.append(key) }
                targets[key, default: []].append(evaluated)
            } else {
                key = TrackRecord.albumGroupKey(for: evaluated.track, missing: [])
                references[key, default: []].append(evaluated)
            }
        }
        // 아티스트 없는 키(`\u{1F}앨범`) 합치기
        let albumPart = { (key: String) in key.split(separator: "\u{1F}", omittingEmptySubsequences: false).last.map(String.init) ?? key }
        let allKeys = Set(targets.keys).union(references.keys)
        for key in order where key.hasPrefix("\u{1F}") {
            let siblings = allKeys.filter { $0 != key && !$0.hasPrefix("single:") && albumPart($0) == albumPart(key) }
            guard siblings.count == 1, let sibling = siblings.first else { continue }
            if targets[sibling] == nil { order.append(sibling) }
            targets[sibling, default: []] += targets[key] ?? []
            targets[key] = nil
        }
        return order.compactMap { key in
            guard let members = targets[key], !members.isEmpty else { return nil }
            return IdentificationGroup(key: key, targets: members, references: references[key] ?? [])
        }
    }
}

/// 식별 결과 → 곡별 제안값과 앨범 결과 레코드
struct ProposalBuilder: Sendable {
    let settings: IdentificationSettings

    func build(group: IdentificationGroup, resolution: GroupResolution) -> (AlbumResolvedRecord?, [ProposalRecord]) {
        let scorer = ConfidenceScorer(weights: settings.weights)
        let views = (group.targets + group.references).map(LocalView.init)
        let now = Date()
        var proposals: [ProposalRecord] = []

        for target in group.targets {
            let outcome = resolution.outcomes[target.id]
            let confidence = scorer.score(outcome?.evidence)
            var record = ProposalRecord(
                persistentID: target.id.hex, albumGroupKey: group.key, source: outcome?.release?.source,
                externalReleaseID: outcome?.release?.id, fieldStatus: [:],
                evidence: ProposalEvidence(match: outcome?.evidence,
                                           reasons: confidence.level == .none && !(outcome?.failureReasons.isEmpty ?? true)
                                               ? outcome?.failureReasons ?? [] : confidence.reasons,
                                           error: resolution.error),
                confidenceScore: confidence.score, confidenceLevel: confidence.level,
                blocksAutoApply: confidence.blocksAutoApply, decision: .pending,
                trackModifiedAt: target.track.modifiedDate?.timeIntervalSince1970, identifiedAt: now,
                missingAtIdentification: target.result.missing)

            if let outcome, let track = outcome.releaseTrack, let release = outcome.release, outcome.evidence != nil {
                record.title = track.title
                record.artist = preferredName(credit: track.artist, ids: track.artistIDs, views: views, artist: outcome.artist)
                record.album = release.title
                record.albumArtist = preferredName(credit: release.artist, ids: release.artistIDs, views: views, artist: outcome.artist)
                record.genre = outcome.crossCheck?.genre
                record.externalRecordingID = track.recordingID
                record.isrc = track.isrc
                // 식별된 릴리스가 로컬 앨범과 다르면(예: 로컬은 베스트 앨범, 식별은 원 앨범) 트랙 번호·연도 등
                // 앨범에 딸린 숫자 값은 제안하지 않는다. 다른 판의 번호가 섞이는 것을 막기 위함. 제목·가수는 녹음 단위라 그대로 쓴다.
                let localAlbum = LocalView(target).existingAlbum
                if outcome.matchedAsAlbum || localAlbum == nil || Normalizer.similarity(localAlbum, release.title) >= 0.8 {
                    record.year = release.year
                    record.trackNo = track.trackNumber > 0 ? track.trackNumber : nil
                    let discTracks = release.tracks?.filter { $0.discNumber == track.discNumber }.count ?? 0
                    record.trackCount = discTracks > 0 ? discTracks : release.trackCount
                    record.discNo = track.discNumber
                    record.discCount = release.discCount
                }
                // 커버는 앨범명이 정확히 같지 않아도(같은 곡이 실린 다른 릴리스라도) 비어 있으면 후보로 제안한다.
                // 앨범명 자체는 이미 식별된 릴리스로 바뀌므로 커버도 그 릴리스 것에 맞춘다 — '이 정보로 다시 식별'과 같은 범위.
                if !target.track.hasArtwork {
                    record.artworkCandidates = artworkCandidates(group: group, outcome: outcome)
                }
                record.artworkRef = record.artworkCandidates.first
            }
            record.fieldStatus = fieldStatus(record, current: target.track)
            // 비어 있는 필수 항목 중 하나도 채울 수 없으면 기록만
            let fillable = target.result.missing.contains { field in
                switch field {
                case .artwork: return record.artworkRef != nil
                case .title: return record.title != nil
                case .artist: return record.artist != nil
                case .album: return record.album != nil
                }
            }
            if confidence.level != .none && !fillable { record.decision = .skipped }
            proposals.append(record)
        }

        var album: AlbumResolvedRecord?
        if let release = resolution.release {
            let scores = proposals.filter { $0.confidenceLevel != .none }.map(\.confidenceScore)
            let average = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
            let weights = settings.weights
            album = AlbumResolvedRecord(
                albumGroupKey: group.key, source: release.source, externalReleaseID: release.id, title: release.title,
                albumArtist: preferredName(credit: release.artist, ids: release.artistIDs, views: views, artist: resolution.artist),
                year: release.year, genre: resolution.crossCheck?.genre, trackCount: release.trackCount, discCount: release.discCount,
                artworkURL: proposals.lazy.compactMap(\.artworkCandidates.first)
                    .first { !$0.hasPrefix("track:") && !$0.hasPrefix("itunes-song:") }
                    .map { String($0.drop { $0 != ":" }.dropFirst()) }, artworkWidth: nil,
                confidenceScore: average,
                confidenceLevel: scores.isEmpty ? .none : average >= weights.highThreshold ? .high : average >= weights.mediumThreshold ? .medium : .low,
                alternatives: resolution.alternatives.map { var copy = $0; copy.tracks = nil; return copy },
                resolvedAt: now)
        }
        return (album, proposals)
    }

    /// 같은 앨범 곡에 이미 쓰인 표기(예: `아이유(IU)`)를 우선하고, 없으면 한글 별칭, 그다음 크레딧 그대로
    private func preferredName(credit: String, ids: [String], views: [LocalView], artist: ArtistMatch?) -> String {
        let soloResolved = artist.flatMap { ids == [$0.id] ? $0 : nil }
        let existing = views.compactMap(\.existingArtist).filter { name in
            Normalizer.artistSimilarity(name, credit) >= 0.85
                || soloResolved.map { [$0.name, $0.koreanName].compactMap { $0 }.contains { Normalizer.artistSimilarity(name, $0) >= 0.85 } } == true
        }
        if let common = mostCommon(existing) { return common }
        if settings.preferKoreanArtistNames, let korean = soloResolved?.koreanName { return korean }
        return credit
    }

    /// 커버 후보 우선순위: 같은 앨범 곡의 기존 커버 → iTunes 1200 → Cover Art Archive (릴리스 → 릴리스 그룹)
    private func artworkCandidates(group: IdentificationGroup, outcome: MemberOutcome) -> [String] {
        var candidates: [String] = []
        // 로컬에서 같은 앨범(앨범명·앨범 아티스트)으로 묶인 완비 곡의 커버
        if !group.isSingle, let sibling = group.references.first(where: { $0.track.hasArtwork }) {
            candidates.append("track:\(sibling.id.hex)")
        }
        return candidates + outcome.artworkCandidates
    }

    func fieldStatus(_ record: ProposalRecord, current track: LibraryTrack) -> [String: FieldStatus] {
        func text(_ proposed: String?, _ current: String?) -> FieldStatus {
            guard let proposed, !Normalizer.clean(proposed).isEmpty else { return .noMatch }
            return Normalizer.compareKey(proposed) == Normalizer.compareKey(current) ? .unchanged : .changed
        }
        func number(_ proposed: Int?, _ current: Int) -> FieldStatus {
            guard let proposed, proposed > 0 else { return .noMatch }
            return proposed == current ? .unchanged : .changed
        }
        let statuses: [ProposalField: FieldStatus] = [
            .title: text(record.title, track.title),
            .artist: text(record.artist, track.artist),
            .album: text(record.album, track.album),
            .albumArtist: text(record.albumArtist, track.albumArtist),
            .genre: text(record.genre, track.genre),
            .year: number(record.year, track.year),
            .trackNumber: number(record.trackNo, track.trackNumber),
            .trackCount: number(record.trackCount, track.trackCount),
            .discNumber: number(record.discNo, track.discNumber),
            .discCount: number(record.discCount, track.discCount),
            .artwork: record.artworkRef == nil ? .noMatch : track.hasArtwork ? .unchanged : .changed,
        ]
        return Dictionary(uniqueKeysWithValues: statuses.map { ($0.key.rawValue, $0.value) })
    }

    private func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return values.max { counts[$0]! < counts[$1]! }
    }
}
