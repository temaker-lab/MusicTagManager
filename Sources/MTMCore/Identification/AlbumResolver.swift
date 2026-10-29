import Foundation

/// 식별 대상 묶음. 같은 (앨범 아티스트, 앨범) 곡끼리 묶고, 앨범명이 없는 곡은 단독 그룹이다.
public struct IdentificationGroup: Sendable {
    public let key: String
    /// 정리 대상(INCOMPLETE) 곡
    public let targets: [EvaluatedTrack]
    /// 같은 앨범의 완비 곡: 수정하지 않고 판단 근거로만 쓴다
    public let references: [EvaluatedTrack]

    public var isSingle: Bool { key.hasPrefix("single:") }
}

/// 곡 하나를 판단할 때 쓰는 값. 비어 있는 항목은 nil이고, 파일명 형태 제목에서 뽑은 단서로 보충한다.
struct LocalView: Sendable {
    let evaluated: EvaluatedTrack
    let hints: TitleHints?

    init(_ evaluated: EvaluatedTrack) {
        self.evaluated = evaluated
        let missing = evaluated.result.missing
        hints = missing.contains(.title) || missing.contains(.artist) ? TitleHints.parse(evaluated.track.title) : nil
    }

    var id: PersistentID { evaluated.track.id }
    var track: LibraryTrack { evaluated.track }
    var missing: [RequiredField] { evaluated.result.missing }

    /// 기존에 입력된 값 (비어 있으면 nil)
    var existingTitle: String? { missing.contains(.title) ? nil : nonEmpty(track.title) }
    var existingArtist: String? { missing.contains(.artist) ? nil : nonEmpty(track.artist) }
    var existingAlbum: String? { missing.contains(.album) ? nil : nonEmpty(track.album) }

    /// 검색·매칭용 (기존 값 또는 단서). 완비 판정이 자리표시로 보고 '비었다'고 표시한 항목이라도,
    /// 실제 태그에 글자가 있으면 마지막 단서로 쓴다 — '이 정보로 다시 식별'이 화면의 값으로 검색하는 것과 같은 범위.
    /// (쓰기·비교·그룹핑은 그대로 existing*만 쓰므로 영향 없음. 검색어로만 쓰이고, 매칭은 유사도 0.85+ 조건이라 오탐 없음)
    var title: String? { existingTitle ?? hints?.title ?? nonEmpty(track.title) }
    var artist: String? { existingArtist ?? hints?.artist ?? nonEmpty(track.artist) }
    var albumArtist: String? { nonEmpty(track.albumArtist) }
    var trackNumber: Int? { track.trackNumber > 0 ? track.trackNumber : hints?.trackNumber }
    var discNumber: Int? { track.discNumber > 0 ? track.discNumber : hints?.discNumber }

    func info(recordingIDs: Set<String> = []) -> LocalTrackInfo {
        LocalTrackInfo(id: id, title: title, durationMs: track.durationMs, trackNumber: trackNumber,
                       discNumber: discNumber, recordingIDs: recordingIDs)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let cleaned = Normalizer.clean(value)
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// 그룹 식별 결과
struct GroupResolution: Sendable {
    var release: ReleaseCandidate?
    var alternatives: [ReleaseCandidate] = []
    /// 다른 소스(iTunes)에서 같은 앨범으로 확인된 릴리스
    var crossCheck: ReleaseCandidate?
    var artist: ArtistMatch?
    var outcomes: [PersistentID: MemberOutcome] = [:]
    var error: String?
}

/// 곡별 결과. 같은 그룹이라도 앨범 단위로 맞지 않아 곡 단위로 식별한 곡은 릴리스가 다를 수 있다.
struct MemberOutcome: Sendable {
    var releaseTrack: ReleaseTrack?
    var release: ReleaseCandidate?
    var crossCheck: ReleaseCandidate?
    var artist: ArtistMatch?
    /// 커버 후보 (우선순위 순): `itunes:<url>`, `caa:<url>`
    var artworkCandidates: [String] = []
    var evidence: MatchEvidence?
    /// 로컬 앨범 전체가 이 릴리스의 트랙리스트에 맞았음 (앨범명 표기가 달라도 같은 앨범)
    var matchedAsAlbum = false
    /// 식별하지 못했을 때 그 이유 (무엇을 시도했고 왜 안 됐는지)
    var failureReasons: [String] = []
}

/// iTunes 확인 결과: 트랙리스트까지 같은 앨범, 또는 제목·가수만 같은 앨범의 커버
struct ITunesCheck: Sendable {
    var matched: ReleaseCandidate?
    var artworkURL: URL?
}

public struct IdentificationSettings: Codable, Sendable, Equatable {
    /// 가수명 표기: 원어(한글) 우선
    public var preferKoreanArtistNames = true
    public var useITunes = true
    public var useAcoustID = true
    public var weights = ConfidenceWeights()

    public init() {}
}

/// 앨범 단위로 릴리스를 하나 정하고, 그 트랙리스트에 곡을 맞춘다.
final class AlbumResolver: Sendable {
    private let musicBrainz: MusicBrainzProvider
    private let itunes: ITunesSearchProvider?
    private let acoustID: AcoustIDProvider?
    private let scorer: ConfidenceScorer
    private let artists = ArtistCache()
    private let itunesChecks = ITunesCheckCache()

    init(musicBrainz: MusicBrainzProvider, itunes: ITunesSearchProvider?, acoustID: AcoustIDProvider?,
         scorer: ConfidenceScorer = ConfidenceScorer()) {
        self.musicBrainz = musicBrainz
        self.itunes = itunes
        self.acoustID = acoustID
        self.scorer = scorer
    }

    /// iTunes는 분당 약 20회로 가장 느린 소스다. 커버가 필요하거나, 교차 확인(+10)으로 HIGH가 될 수 있는 곡이 있을 때만 조회한다.
    private func needsITunes(missingArtwork: Bool, evidences: [MatchEvidence]) -> Bool {
        guard itunes != nil else { return false }
        if missingArtwork { return true }
        let weights = scorer.weights
        return evidences.contains { evidence in
            let score = scorer.score(evidence).score
            return score < weights.highThreshold && score + weights.sourcesAgree >= weights.highThreshold
        }
    }

    func resolve(_ group: IdentificationGroup) async throws -> GroupResolution {
        group.isSingle ? try await resolveSingle(LocalView(group.targets[0])) : try await resolveAlbum(group)
    }

    // MARK: - 앨범 그룹

    private func resolveAlbum(_ group: IdentificationGroup) async throws -> GroupResolution {
        let targets = group.targets.map(LocalView.init)
        let everyone = targets + group.references.map(LocalView.init)
        guard let albumTitle = mostCommon(everyone.compactMap(\.existingAlbum)) else {
            return GroupResolution(error: MTMLoc.t("resolve.noAlbumName", "앨범명 없음"))
        }
        let artistName = mostCommon(everyone.compactMap(\.albumArtist)) ?? mostCommon(everyone.compactMap(\.artist))
        var resolution = GroupResolution()
        resolution.artist = try await artist(named: artistName)

        var releases: [ReleaseCandidate] = []
        for variant in Normalizer.searchVariants(albumTitle) where releases.isEmpty {
            releases = try await musicBrainz.searchReleases(title: variant, artistID: resolution.artist?.id)
        }
        if releases.isEmpty, resolution.artist != nil {
            // 아티스트 판별이 틀렸을 수 있으므로 앨범명만으로 한 번 더
            releases = try await musicBrainz.searchReleases(title: albumTitle, artistID: nil)
                .filter { artistName == nil || Normalizer.artistSimilarity(artistName, $0.artist) >= 0.5 }
        }
        let localCount = everyone.count
        let ranked = releases
            .map { (release: $0, score: albumScore($0, albumTitle: albumTitle, artistName: artistName,
                                                   artist: resolution.artist, localCount: localCount)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score
                : ReleasePreference.isPreferred($0.release, over: $1.release, preferHangul: Normalizer.containsHangul(albumTitle)) }
        resolution.alternatives = Array(ranked.prefix(5).map(\.release))
        let ambiguous = ranked.count >= 2 && ranked[0].score - ranked[1].score < 10 && !sameEdition(ranked[0].release, ranked[1].release)

        var matches: [PersistentID: TrackMatch] = [:]
        if let top = ranked.first, top.score >= 50 {
            let release = try await musicBrainz.release(id: top.release.id)
            resolution.release = release
            matches = TrackMatcher.match(everyone.map { $0.info() }, to: release.tracks ?? [])
        }

        // 오디오 지문: 대표 곡 1~2개 (매칭이 안 된 곡 우선). 같은 앨범의 다른 곡에 확신을 더해 준다.
        var fingerprinted: [PersistentID: Set<String>] = [:]
        if let acoustID {
            let unmatched = targets.filter { matches[$0.id] == nil }
            var found: [FingerprintMatch] = []
            for probe in (unmatched.isEmpty ? targets : unmatched).prefix(2) {
                guard let url = probe.track.fileURL, Self.fingerprintBlockReason(probe.track) == nil else { continue }
                let probeMatches = try await fingerprintMatches(for: url, using: acoustID)
                if !probeMatches.isEmpty { fingerprinted[probe.id] = Set(probeMatches.map(\.recordingID)) }
                found += probeMatches
            }
            let allIDs = Set(found.map(\.recordingID))
            let releaseRecordingIDs = Set((resolution.release?.tracks ?? []).compactMap(\.recordingID))
            if !allIDs.isEmpty, releaseRecordingIDs.isDisjoint(with: allIDs),
               let better = try await releaseFromRecordings(Array(found.prefix(3)), albumTitle: albumTitle) {
                let betterMatches = TrackMatcher.match(everyone.map { $0.info(recordingIDs: fingerprinted[$0.id] ?? []) },
                                                       to: better.tracks ?? [])
                if betterMatches.count >= matches.count {
                    resolution.release = better
                    resolution.alternatives.insert(better, at: 0)
                }
            }
            if let release = resolution.release {
                matches = TrackMatcher.match(everyone.map { $0.info(recordingIDs: fingerprinted[$0.id] ?? []) }, to: release.tracks ?? [])
            }
        }
        if let release = resolution.release {
            let fingerprintConfirmed = matches.values.contains { $0.byFingerprint }
            // 로컬 앨범과 같은 앨범인가: 앨범명이 비슷하거나, 3곡 이상 앨범의 80% 이상이 트랙리스트에 맞을 때만.
            // (Phase 3 실측: 곡 1개짜리 싱글 앨범이 지문으로 정규 앨범에 맞아 다른 앨범 커버가 들어간 사례)
            let sameAlbum = Normalizer.similarity(albumTitle, release.title) >= 0.8
                || (everyone.count >= 3 && Double(matches.count) >= 0.8 * Double(everyone.count))
            let tagTrackCount = mostCommon(everyone.map(\.track.trackCount).filter { $0 > 0 })
            let trackCountMatches = release.trackCount == localCount || tagTrackCount == release.trackCount

            var matched: [(view: LocalView, match: TrackMatch, evidence: MatchEvidence)] = []
            for view in targets {
                guard let match = matches[view.id] else { continue }
                var evidence = baseEvidence(view, track: match.releaseTrack, artist: resolution.artist)
                evidence.titleSimilarity = view.title == nil ? nil : match.titleSimilarity
                evidence.albumSimilarity = view.existingAlbum.map { Normalizer.similarity($0, release.title) }
                evidence.durationDeltaMs = match.durationDeltaMs
                evidence.fingerprintMatched = match.byFingerprint
                evidence.albumFingerprintConfirmed = fingerprintConfirmed && !match.byFingerprint
                evidence.trackCountMatches = trackCountMatches
                evidence.ambiguous = ambiguous && !fingerprintConfirmed
                matched.append((view, match, evidence))
            }
            let check = needsITunes(missingArtwork: matched.contains { !$0.view.track.hasArtwork }, evidences: matched.map(\.evidence))
                ? await itunesCheck(release, artistName: artistName, albumTitle: albumTitle) : ITunesCheck()
            resolution.crossCheck = check.matched
            let artwork = artworkCandidates(release: release, check: check)
            for (view, match, var evidence) in matched {
                evidence.sourcesAgree = check.matched != nil
                let covers = songCoverTokenAppended(artwork, view: view)
                resolution.outcomes[view.id] = MemberOutcome(
                    releaseTrack: match.releaseTrack, release: release, crossCheck: check.matched,
                    artist: resolution.artist, artworkCandidates: covers, evidence: evidence, matchedAsAlbum: sameAlbum)
            }
        }

        // 앨범 단위로 맞지 않은 곡(컴필레이션, MusicBrainz에 없는 앨범 등)은 곡 단위로 식별한다
        for view in targets where resolution.outcomes[view.id] == nil {
            guard acoustID != nil || view.title != nil else {
                resolution.outcomes[view.id] = MemberOutcome(failureReasons: [Self.noTitleReason, Self.noAcoustIDReason])
                continue
            }
            let single = try await resolveSingle(view)
            resolution.outcomes[view.id] = single.outcomes[view.id] ?? MemberOutcome()
        }
        return resolution
    }

    /// 앨범 후보 점수 (0~95): 앨범명 50, 아티스트 20, 트랙 수 15, 원 릴리스 여부 10
    private func albumScore(_ release: ReleaseCandidate, albumTitle: String, artistName: String?,
                            artist: ArtistMatch?, localCount: Int) -> Double {
        var score = Normalizer.similarity(albumTitle, release.title) * 50
        if let artist, release.artistIDs.contains(artist.id) {
            score += 20
        } else if let artistName {
            score += Normalizer.artistSimilarity(artistName, release.artist) * 20
        } else {
            score += 10
        }
        if release.trackCount >= localCount { score += 10 }
        if release.trackCount == localCount { score += 5 }
        if !release.isSecondaryRelease { score += 10 }
        return score
    }

    /// 같은 앨범의 다른 판(재발매·다른 바코드)은 경쟁 후보로 보지 않는다
    private func sameEdition(_ a: ReleaseCandidate, _ b: ReleaseCandidate) -> Bool {
        Normalizer.matchKey(a.title) == Normalizer.matchKey(b.title) && a.trackCount == b.trackCount
    }

    // MARK: - 단독 곡 (앨범명 없음)

    static var noTitleReason: String { MTMLoc.t("resolve.noTitle", "검색할 제목 없음 (곡 제목이 비어 있고 파일명에서도 찾지 못함)") }
    static var noAcoustIDReason: String { MTMLoc.t("resolve.noAcoustID", "오디오 지문 확인 안 함 (AcoustID 꺼짐 또는 API 키 없음)") }

    /// 오디오 지문을 아예 만들 수 없는 곡이면 그 사유를 돌려준다 (만들 수 있으면 nil).
    /// 클라우드 전용·DRM 보호·파일 없음은 지문이 불가능하므로 제목·가수 텍스트 식별로만 진행한다.
    static func fingerprintBlockReason(_ track: LibraryTrack) -> String? {
        if track.isDRMProtected { return MTMLoc.t("resolve.fp.drm", "DRM 보호 곡이라 오디오 지문을 만들 수 없습니다 (제목·가수로만 식별)") }
        guard let url = track.fileURL else {
            return track.isCloud
                ? MTMLoc.t("resolve.fp.cloud", "클라우드 전용 곡 — Music에서 먼저 다운로드하면 오디오 지문으로 식별할 수 있습니다")
                : MTMLoc.t("resolve.fp.noLocation", "파일 위치를 알 수 없어 오디오 지문을 만들 수 없습니다")
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            return MTMLoc.f("resolve.fp.fileMissing", "로컬 파일을 찾을 수 없어 오디오 지문을 만들 수 없습니다: %@", url.lastPathComponent)
        }
        return nil
    }

    func resolveSingle(_ view: LocalView) async throws -> GroupResolution {
        var resolution = GroupResolution()
        var candidates: [RecordingCandidate] = []
        var byFingerprint = false
        var ambiguous = false
        var reasons: [String] = []
        func failed() -> GroupResolution {
            resolution.outcomes[view.id] = MemberOutcome(failureReasons: reasons)
            return resolution
        }

        // 지문을 쓸 수 있으면 먼저 확인한다: 앨범 근거가 없는 곡은 지문 없이는 높은 신뢰도를 얻기 어렵다
        var fingerprinted: [FingerprintMatch] = []
        if let acoustID {
            if let reason = Self.fingerprintBlockReason(view.track) {
                reasons.append(reason)
            } else if let url = view.track.fileURL {
                fingerprinted = try await fingerprintMatches(for: url, using: acoustID)
                if fingerprinted.isEmpty { reasons.append(MTMLoc.t("resolve.fp.noMatch", "오디오 지문: AcoustID에 일치하는 녹음 없음")) }
            }
        } else {
            reasons.append(Self.noAcoustIDReason)
        }

        if let title = view.title {
            let artistOptions = try await artistCandidates(named: view.artist)
            resolution.artist = artistOptions.first
            if let artistName = view.artist, artistOptions.isEmpty {
                reasons.append(MTMLoc.f("resolve.artistNotFound", "가수 ‘%@’을(를) MusicBrainz에서 찾지 못함 (가수 없이 검색)", artistName))
            }
            func matching(_ found: [RecordingCandidate], artist: ArtistMatch?) -> [RecordingCandidate] {
                found.filter { candidate in
                    guard Normalizer.similarity(title, candidate.title) >= 0.85,
                          Normalizer.versionTags(title) == Normalizer.versionTags(candidate.title) else { return false }
                    if let artist { return candidate.artistIDs.contains(artist.id) }
                    if let artistName = view.artist {
                        // 가수 조건 없이 검색한 결과: 크레딧 이름이 비슷하거나 이름이 맞는 아티스트 후보의 곡이면 인정
                        return Normalizer.artistSimilarity(artistName, candidate.artist) >= 0.6
                            || artistOptions.contains { candidate.artistIDs.contains($0.id) }
                    }
                    return durationDelta(candidate, view) <= 3_000
                }
                .sorted { durationDelta($0, view) < durationDelta($1, view) }
            }
            // 기호 앞뒤 띄어쓰기가 달라 못 찾는 경우(‘2 + 1’ ↔ ‘2+1’)를 위해 검색어 변형을 차례로 시도한다
            let variants = Normalizer.searchVariants(title)
            func search(artist: ArtistMatch?, durationMs: Int?) async throws -> (found: [RecordingCandidate], matched: [RecordingCandidate]) {
                var first: [RecordingCandidate]?
                for variant in variants {
                    let found = try await musicBrainz.searchRecordings(title: variant, artistID: artist?.id, durationMs: durationMs)
                    if first == nil { first = found }
                    let matched = matching(found, artist: artist)
                    if !matched.isEmpty { return (found, matched) }
                }
                return (first ?? [], [])
            }
            // 가수를 모르면 제목 + 길이(±3초)로 검색
            var (found, matched) = try await search(artist: resolution.artist,
                                                    durationMs: view.artist == nil ? view.track.durationMs : nil)
            candidates = matched
            // 같은 이름·별칭의 다른 아티스트일 수 있다: 다음 후보 아티스트로 (최대 2명 더)
            for other in artistOptions.dropFirst().prefix(2) where candidates.isEmpty {
                let (more, matched) = try await search(artist: other, durationMs: nil)
                if !matched.isEmpty {
                    resolution.artist = other
                    candidates = matched
                    found = more
                }
            }
            // 그래도 없으면 가수 조건 없이 제목만으로 검색해 크레딧 이름으로 확인
            if candidates.isEmpty, view.artist != nil, resolution.artist != nil {
                let (loose, matched) = try await search(artist: nil, durationMs: nil)
                if !matched.isEmpty {
                    resolution.artist = artistOptions.first { option in matched[0].artistIDs.contains(option.id) }
                    candidates = matched
                }
                if found.isEmpty { found = loose }
            }
            // 가수를 모르는 채로 서로 다른 가수의 후보가 여럿이면 확신할 수 없다
            ambiguous = view.artist == nil && Set(candidates.map { Normalizer.matchKey($0.artist) }).count > 1
            let searched = MTMLoc.f("resolve.searchMB", "MusicBrainz 검색 ‘%@’", title) + (view.artist.map { MTMLoc.f("resolve.searchArtistSuffix", " · %@", $0) } ?? MTMLoc.t("resolve.searchNoArtist", " (가수 모름 → 제목+길이)"))
            if found.isEmpty {
                reasons.append(MTMLoc.f("resolve.searchNoResult", "%@: 결과 없음", searched))
            } else if candidates.isEmpty {
                let what = view.artist == nil ? MTMLoc.t("resolve.searchWhat.titleLen", "제목·길이(±3초)") : MTMLoc.t("resolve.searchWhat.titleArtist", "제목·가수")
                reasons.append(MTMLoc.f("resolve.searchNoMatch", "%1$@: 결과 %3$d건 중 %2$@가 맞는 곡 없음 (예: %4$@ — %5$@)", searched, what, found.count, found[0].title, found[0].artist))
            }
        } else {
            reasons.append(Self.noTitleReason)
        }

        // 지문 녹음 중 파일의 제목(기존 값이나 파일명 단서)과 같은 곡만 믿는다.
        // AcoustID는 한 지문에 다른 녹음을 함께 묶기도 한다 (Phase 3 실측: Kryptonite → The Road I'm On).
        var fingerprintRecordings: [RecordingCandidate] = []
        for match in fingerprinted.prefix(3) {
            fingerprintRecordings.append(try await recording(for: match))
        }
        let sameSong = fingerprintRecordings.filter { recording in
            guard let title = view.title else { return true }
            return Normalizer.similarity(title, recording.title) >= 0.85
                && Normalizer.versionTags(title) == Normalizer.versionTags(recording.title)
        }
        if !sameSong.isEmpty {
            // 같은 곡이 확인됨: 지문 녹음과 텍스트 후보의 수록 앨범을 함께 보고 원 앨범을 고른다
            // (지문 녹음 3개가 모두 믹스테이프판이어도 원 앨범을 고를 수 있게)
            candidates = sameSong + candidates.filter { candidate in !sameSong.contains { $0.id == candidate.id } }
            byFingerprint = true
            ambiguous = false
        } else if candidates.isEmpty, !fingerprintRecordings.isEmpty {
            // 텍스트로 찾지 못했고 지문은 제목이 다른 곡: 지문 결과를 쓰되 근거에서 제목 불일치로 감점된다
            candidates = fingerprintRecordings
            byFingerprint = true
        }
        guard let first = candidates.first else {
            // 지문·MusicBrainz 모두 실패 → iTunes 노래 검색으로 마지막 폴백 (제목·가수 텍스트)
            if let resolved = try await resolveViaITunes(view, reasons: &reasons) {
                resolution.release = resolved.release
                resolution.alternatives = [resolved.release]
                resolution.outcomes[view.id] = resolved.outcome
                return resolution
            }
            return failed()
        }

        let preferHangul = Normalizer.containsHangul(first.title) || Normalizer.containsHangul(view.title)
        let pool = (byFingerprint ? candidates : [first]).flatMap { recording in recording.appearances.map { ($0, recording) } }
        var ordered = ReleasePreference.sorted(Array(Set(pool.map(\.0.release))), preferHangul: preferHangul)
        // 기존 앨범명이나 파일명의 앨범명(예: 컴필레이션 수록곡)이 있으면 그 앨범을 먼저 고른다
        if let knownAlbum = view.existingAlbum ?? view.hints?.album {
            let named = ordered.filter { Normalizer.similarity(knownAlbum, $0.title) >= 0.8 }
            ordered = named + ordered.filter { candidate in !named.contains { $0.id == candidate.id } }
        }
        resolution.alternatives = Array(ordered.prefix(5))
        guard let best = ordered.first,
              let (appearance, recording) = pool.first(where: { $0.0.release.id == best.id }) else {
            reasons.append(MTMLoc.f("resolve.noAlbumForRecording", "찾은 곡 ‘%@’이(가) 실린 앨범 정보가 없음", first.title))
            return failed()
        }
        let release = try await musicBrainz.release(id: best.id)
        resolution.release = release
        if resolution.artist == nil {
            resolution.artist = try await artist(named: recording.artist).flatMap { recording.artistIDs.contains($0.id) ? $0 : nil }
        }

        let track = release.tracks?.first { $0.recordingID == recording.id }
            ?? ReleaseTrack(discNumber: appearance.discNumber, trackNumber: appearance.trackNumber,
                            title: recording.title, artist: recording.artist, artistIDs: recording.artistIDs,
                            durationMs: recording.durationMs, recordingID: recording.id, isrc: recording.isrc)

        var evidence = baseEvidence(view, track: track, artist: resolution.artist)
        evidence.titleSimilarity = view.title.map { Normalizer.similarity($0, track.title) }
        evidence.durationDeltaMs = track.durationMs.map { abs($0 - view.track.durationMs) }
        evidence.fingerprintMatched = byFingerprint
        evidence.ambiguous = ambiguous
        let check = needsITunes(missingArtwork: !view.track.hasArtwork, evidences: [evidence])
            ? await itunesCheck(release, artistName: view.artist ?? recording.artist, albumTitle: release.title) : ITunesCheck()
        resolution.crossCheck = check.matched
        evidence.sourcesAgree = check.matched != nil
        let covers = songCoverTokenAppended(artworkCandidates(release: release, check: check), view: view)
        resolution.outcomes[view.id] = MemberOutcome(
            releaseTrack: track, release: release, crossCheck: check.matched, artist: resolution.artist,
            artworkCandidates: covers, evidence: evidence)
        return resolution
    }

    /// 앨범명이 없는 곡끼리 정리 (지시서 §2.6): 같은 폴더의 단독 곡 중 하나가 지문으로 어떤 릴리스에 확인되면,
    /// 나머지 곡도 그 트랙리스트에서 제목과 트랙 번호(또는 길이)가 맞을 때 같은 릴리스로 통일한다.
    func consolidateSingles(_ items: [(IdentificationGroup, GroupResolution)]) -> [(IdentificationGroup, GroupResolution)] {
        var result = items
        let folders = Dictionary(grouping: items.indices) { index in
            items[index].0.targets.first?.track.fileURL?.deletingLastPathComponent().path ?? ""
        }
        for (folder, indices) in folders where !folder.isEmpty && indices.count >= 2 {
            let anchors = indices.filter { index in
                let (group, resolution) = items[index]
                return group.targets.first.flatMap { resolution.outcomes[$0.id]?.evidence?.fingerprintMatched } == true
                    && resolution.release?.tracks != nil
            }
            for anchorIndex in anchors {
                let anchor = items[anchorIndex].1
                guard let release = anchor.release, let tracks = release.tracks,
                      let anchorOutcome = items[anchorIndex].0.targets.first.flatMap({ anchor.outcomes[$0.id] }) else { continue }
                for index in indices where index != anchorIndex {
                    let (group, current) = result[index]
                    guard let target = group.targets.first,
                          current.outcomes[target.id]?.evidence?.fingerprintMatched != true,
                          current.release?.id != release.id || current.outcomes[target.id]?.evidence?.albumFingerprintConfirmed != true
                    else { continue }
                    let view = LocalView(target)
                    guard let title = view.title,
                          let track = tracks.first(where: { track in
                              Normalizer.similarity(title, track.title) >= 0.85
                                  && Normalizer.versionTags(title) == Normalizer.versionTags(track.title)
                                  && (view.trackNumber == track.trackNumber
                                      || track.durationMs.map { abs($0 - view.track.durationMs) <= 3_000 } == true)
                          }) else { continue }
                    var updated = GroupResolution(release: release, alternatives: [release] + current.alternatives.filter { $0.id != release.id },
                                                  crossCheck: anchor.crossCheck, artist: anchor.artist)
                    var evidence = baseEvidence(view, track: track, artist: anchor.artist)
                    evidence.titleSimilarity = Normalizer.similarity(title, track.title)
                    evidence.durationDeltaMs = track.durationMs.map { abs($0 - view.track.durationMs) }
                    evidence.albumFingerprintConfirmed = true
                    evidence.sourcesAgree = anchor.crossCheck != nil
                    updated.outcomes[target.id] = MemberOutcome(
                        releaseTrack: track, release: release, crossCheck: anchor.crossCheck, artist: anchor.artist,
                        artworkCandidates: anchorOutcome.artworkCandidates, evidence: evidence)
                    result[index].1 = updated
                }
            }
        }
        return result
    }

    /// AcoustID가 녹음 정보를 함께 줬으면 그대로 쓰고, 아니면 MusicBrainz에서 조회
    private func recording(for match: FingerprintMatch) async throws -> RecordingCandidate {
        if let recording = match.recording, !recording.appearances.isEmpty { return recording }
        return try await musicBrainz.recording(id: match.recordingID)
    }

    private func durationDelta(_ recording: RecordingCandidate, _ view: LocalView) -> Int {
        recording.durationMs.map { abs($0 - view.track.durationMs) } ?? Int.max / 2
    }

    // MARK: - 공통

    /// 기존 값과의 일치·불일치 근거 (가수명은 MusicBrainz 영문 크레딧과 한글 별칭을 모두 비교)
    private func baseEvidence(_ view: LocalView, track: ReleaseTrack, artist: ArtistMatch?) -> MatchEvidence {
        var evidence = MatchEvidence()
        if let localArtist = view.artist {
            var names = [track.artist]
            if let artist, track.artistIDs.contains(artist.id) {
                names += [artist.name, artist.koreanName].compactMap { $0 }
            }
            let similarity = names.map { Normalizer.artistSimilarity(localArtist, $0) }.max() ?? 0
            evidence.artistSimilarity = similarity
            // 파일명 단서의 가수와 달라도 감점 (Phase 3 실측: '98 degrees - Last Christmas' → Human Nature)
            if similarity < 0.5 {
                evidence.coreMismatch = true
                // 자동 적용 금지는 기존에 입력된 가수가 바뀌는 경우
                if view.existingArtist != nil { evidence.artistReplaced = true }
            }
        }
        // 기존 제목뿐 아니라 파일명 단서의 제목과 다른 곡이어도 감점
        if let title = view.title, Normalizer.similarity(title, track.title) < 0.5 {
            evidence.coreMismatch = true
        }
        return evidence
    }

    private func artist(named name: String?) async throws -> ArtistMatch? {
        try await artistCandidates(named: name).first
    }

    /// 이름이 맞는 아티스트 후보 전부 (같은 이름·별칭의 아티스트가 여럿일 수 있음)
    private func artistCandidates(named name: String?) async throws -> [ArtistMatch] {
        guard let name, !Normalizer.matchKey(name).isEmpty else { return [] }
        if let cached = await artists.get(name) { return cached }
        let matches = try await musicBrainz.resolveArtists(named: name)
        await artists.set(name, matches)
        return matches
    }

    /// 지문 점수 0.8 이상인 녹음 (점수 높은 순)
    private func fingerprintMatches(for file: URL, using acoustID: AcoustIDProvider) async throws -> [FingerprintMatch] {
        do {
            let fingerprint = try await acoustID.fingerprint(of: file)
            return Array(try await acoustID.lookup(fingerprint).filter { $0.score >= 0.8 }.prefix(5))
        } catch let error as HTTPError where error == .offline {
            throw error
        } catch {
            Log.identify.error("지문 식별 실패 \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 지문으로 얻은 녹음들이 실린 릴리스 중 하나를 고른다 (앨범명이 비슷한 것 우선, 그다음 Phase 0 규칙)
    private func releaseFromRecordings(_ found: [FingerprintMatch], albumTitle: String) async throws -> ReleaseCandidate? {
        var pool: [ReleaseCandidate] = []
        for match in found {
            pool += try await recording(for: match).appearances.map(\.release)
        }
        let similar = pool.filter { Normalizer.similarity(albumTitle, $0.title) >= 0.6 }
        let ordered = ReleasePreference.sorted(similar.isEmpty ? pool : similar, preferHangul: Normalizer.containsHangul(albumTitle))
        guard let best = ordered.first else { return nil }
        return try await musicBrainz.release(id: best.id)
    }

    /// 지문·MusicBrainz로 못 찾은 곡을 iTunes 노래 검색으로 찾는다 (제목·가수 텍스트, 마지막 폴백).
    /// 맞는 곡이 있으면 그 곡이 실린 앨범을 조회해 릴리스·트랙·커버 후보로 결과를 만든다.
    private func resolveViaITunes(_ view: LocalView, reasons: inout [String]) async throws
        -> (release: ReleaseCandidate, outcome: MemberOutcome)? {
        guard let itunes, let title = view.title else { return nil }
        let term = [view.artist, title].compactMap { $0 }.joined(separator: " ")
        guard let songs = try? await itunes.searchSongs(term: term) else { return nil }
        guard let match = songs.first(where: { song in
            Normalizer.similarity(title, song.title) >= 0.85
                && Normalizer.versionTags(title) == Normalizer.versionTags(song.title)
                && (view.artist.map { Normalizer.artistSimilarity($0, song.artist) >= 0.6 } ?? true)
        }) else {
            reasons.append(MTMLoc.f("resolve.itunesNoMatch", "iTunes 노래 검색 ‘%@’: 제목·가수가 맞는 곡 없음", title))
            return nil
        }
        guard let release = try? await itunes.album(id: match.collectionID) else { return nil }
        let track = release.tracks?.first { $0.trackNumber == match.trackNumber && $0.discNumber == match.discNumber }
            ?? release.tracks?.first { Normalizer.similarity(title, $0.title) >= 0.85 }
            ?? ReleaseTrack(discNumber: match.discNumber, trackNumber: match.trackNumber, title: match.title,
                            artist: match.artist, artistIDs: [], durationMs: match.durationMs, recordingID: nil)
        var evidence = baseEvidence(view, track: track, artist: nil)
        evidence.titleSimilarity = Normalizer.similarity(title, track.title)
        evidence.durationDeltaMs = track.durationMs.map { abs($0 - view.track.durationMs) }
        let artwork = release.artworkURL.map { ["itunes:\($0.absoluteString)"] } ?? []
        let outcome = MemberOutcome(releaseTrack: track, release: release, crossCheck: nil, artist: nil,
                                    artworkCandidates: artwork, evidence: evidence)
        return (release, outcome)
    }

    /// 커버가 필요한 곡(기존 커버 없음)에 iTunes 노래 검색 '지연 후보' 토큰을 맨 뒤에 덧붙인다.
    /// 식별 단계에서는 네트워크를 전혀 쓰지 않고 토큰만 남긴다 — ArtworkService가 앞의 릴리스 커버(CAA·iTunes 앨범)가
    /// 모두 실패할 때만 이 토큰을 풀어 iTunes 노래 검색을 수행한다. 덕분에 대량 식별이 iTunes 호출로 느려지지 않는다.
    private func songCoverTokenAppended(_ covers: [String], view: LocalView) -> [String] {
        guard itunes != nil, !view.track.hasArtwork, let title = view.title, !title.isEmpty else { return covers }
        return covers + ["itunes-song:\(title)\u{1F}\(view.artist ?? "")"]
    }

    /// iTunes에서 같은 앨범을 찾는다. 한국 앨범은 영문 표기로 나오므로 제목 대신 트랙별 길이로 비교한다.
    /// 트랙리스트가 같지 않아도 제목·가수가 같은 앨범이면 커버 후보로는 쓴다.
    private func itunesCheck(_ release: ReleaseCandidate, artistName: String?, albumTitle: String) async -> ITunesCheck {
        guard let itunes else { return ITunesCheck() }
        if let cached = await itunesChecks.get(release.id) { return cached }
        let check = await fetchITunesCheck(itunes, release, artistName: artistName, albumTitle: albumTitle)
        await itunesChecks.set(release.id, check)
        return check
    }

    private func fetchITunesCheck(_ itunes: ITunesSearchProvider, _ release: ReleaseCandidate, artistName: String?,
                                  albumTitle: String) async -> ITunesCheck {
        let term = [artistName, albumTitle].compactMap { $0 }.joined(separator: " ")
        guard let albums = try? await itunes.searchAlbums(term: term) else { return ITunesCheck() }
        var check = ITunesCheck()
        if let tracks = release.tracks, !tracks.isEmpty {
            for candidate in albums.filter({ abs($0.trackCount - release.trackCount) <= 1 }).prefix(1) {
                guard let album = try? await itunes.album(id: candidate.id) else { continue }
                if Self.sameTracklist(tracks, album.tracks ?? []) {
                    check.matched = album
                    check.artworkURL = album.artworkURL
                    return check
                }
            }
        }
        let named = albums.first { album in
            max(Normalizer.similarity(album.title, release.title), Normalizer.similarity(album.title, albumTitle)) >= 0.9
                && (artistName.map { Normalizer.artistSimilarity($0, album.artist) >= 0.85 } ?? false
                    || Normalizer.artistSimilarity(release.artist, album.artist) >= 0.85)
        }
        check.artworkURL = named?.artworkURL
        return check
    }

    /// 외부 커버 후보 (우선순위: iTunes 1200 → 이 릴리스의 Cover Art Archive → 같은 릴리스 그룹의 대표 커버).
    /// 같은 앨범 곡의 기존 커버는 제안 단계에서 맨 앞에 둔다. 실제 다운로드·검증은 적용 단계에서 한다.
    private func artworkCandidates(release: ReleaseCandidate, check: ITunesCheck) -> [String] {
        var candidates: [String] = []
        if let url = check.artworkURL { candidates.append("itunes:\(url.absoluteString)") }
        if let url = release.artworkURL { candidates.append("caa:\(url.absoluteString)") }
        if release.source == .musicbrainz, let group = release.releaseGroupID {
            candidates.append("caa:https://coverartarchive.org/release-group/\(group)/front-1200")
        }
        return candidates
    }

    static func sameTracklist(_ a: [ReleaseTrack], _ b: [ReleaseTrack]) -> Bool {
        let lookup = Dictionary(b.map { ("\($0.discNumber)-\($0.trackNumber)", $0) }, uniquingKeysWith: { first, _ in first })
        var compared = 0, agreed = 0
        for track in a {
            guard let other = lookup["\(track.discNumber)-\(track.trackNumber)"],
                  let x = track.durationMs, let y = other.durationMs else { continue }
            compared += 1
            if abs(x - y) <= 3_000 { agreed += 1 }
        }
        return compared > 0 && Double(agreed) >= 0.7 * Double(min(a.count, b.count))
    }

    private func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return values.max { counts[$0]! < counts[$1]! }
    }
}

/// 같은 릴리스는 iTunes를 한 번만 확인한다 (같은 앨범의 단독 곡 여럿, 동시 처리 그룹 간 공유)
actor ITunesCheckCache {
    private var values: [String: ITunesCheck] = [:]

    func get(_ releaseID: String) -> ITunesCheck? { values[releaseID] }
    func set(_ releaseID: String, _ check: ITunesCheck) { values[releaseID] = check }
}

actor ArtistCache {
    private var values: [String: [ArtistMatch]] = [:]

    func get(_ name: String) -> [ArtistMatch]? { values[Normalizer.compareKey(name)] }
    func set(_ name: String, _ matches: [ArtistMatch]) { values[Normalizer.compareKey(name)] = matches }
}
