import Foundation

public enum FieldValue: Codable, Equatable, Sendable {
    case text(String)
    case number(Int)
}

/// Music 앱에서 읽은 곡의 현재 값
public struct TrackFields: Codable, Equatable, Sendable {
    public var title = ""
    public var artist = ""
    public var album = ""
    public var albumArtist = ""
    public var genre = ""
    public var year = 0
    public var trackNumber = 0
    public var trackCount = 0
    public var discNumber = 0
    public var discCount = 0
    public var artworkCount = 0
    /// 파일 위치 (태그가 바뀌면 Music이 옮길 수 있다)
    public var location: String?

    public init() {}

    public func value(of field: ProposalField) -> FieldValue? {
        switch field {
        case .title: return .text(title)
        case .artist: return .text(artist)
        case .album: return .text(album)
        case .albumArtist: return .text(albumArtist)
        case .genre: return .text(genre)
        case .year: return .number(year)
        case .trackNumber: return .number(trackNumber)
        case .trackCount: return .number(trackCount)
        case .discNumber: return .number(discNumber)
        case .discCount: return .number(discCount)
        case .artwork: return nil
        }
    }

    public mutating func set(_ field: ProposalField, _ value: FieldValue) {
        switch (field, value) {
        case (.title, .text(let v)): title = v
        case (.artist, .text(let v)): artist = v
        case (.album, .text(let v)): album = v
        case (.albumArtist, .text(let v)): albumArtist = v
        case (.genre, .text(let v)): genre = v
        case (.year, .number(let v)): year = v
        case (.trackNumber, .number(let v)): trackNumber = v
        case (.trackCount, .number(let v)): trackCount = v
        case (.discNumber, .number(let v)): discNumber = v
        case (.discCount, .number(let v)): discCount = v
        default: break
        }
    }

    /// 완비 판정을 다시 하기 위한 변환 (플레이스홀더 규칙 적용)
    func libraryTrack(id: PersistentID) -> LibraryTrack {
        LibraryTrack(id: id, title: title, artist: artist, albumArtist: albumArtist, album: album, genre: genre,
                     year: year, trackNumber: trackNumber, trackCount: trackCount, discNumber: discNumber,
                     discCount: discCount, hasArtwork: artworkCount > 0, fileURL: location.map { URL(fileURLWithPath: $0) })
    }
}

public enum ArtworkAction: Codable, Equatable, Sendable {
    /// 처리된 JPEG 파일로 커버 설정 (커버가 없던 곡이면 새 커버 1개)
    case set(path: String, source: String)
    /// 되돌리기: 이 앱이 추가했던 커버 삭제
    case delete
    /// 되돌리기: 백업해 둔 원래 커버로 복원
    case restore(path: String)
}

/// 실제로 Music에 쓸 변경 (값이 있는 필드만 쓴다)
public struct TrackChange: Codable, Equatable, Sendable {
    public var values: [String: FieldValue] = [:]
    public var artwork: ArtworkAction?

    public init(values: [String: FieldValue] = [:], artwork: ArtworkAction? = nil) {
        self.values = values
        self.artwork = artwork
    }

    public var isEmpty: Bool { values.isEmpty && artwork == nil }

    public var fields: [ProposalField] {
        ProposalField.allCases.filter { values[$0.rawValue] != nil || ($0 == .artwork && artwork != nil) }
    }

    public func value(of field: ProposalField) -> FieldValue? { values[field.rawValue] }
}

/// 스캔 당시 값. 쓰기 직전 Music 값과 다르면 사용자가 그 사이 직접 고친 것으로 보고 적용하지 않는다(§8).
public struct ScannedValues: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var hasArtwork: Bool

    public init(_ track: LibraryTrack) {
        title = track.title
        artist = track.artist ?? ""
        album = track.album ?? ""
        albumArtist = track.albumArtist ?? ""
        hasArtwork = track.hasArtwork
    }

    /// Music 스크립팅으로 읽은 값으로 기준을 만든다 (적용 때 읽는 값과 같은 출처 → 교차-출처 오탐 방지).
    public init(_ fields: TrackFields) {
        title = fields.title
        artist = fields.artist
        album = fields.album
        albumArtist = fields.albumArtist
        hasArtwork = fields.artworkCount > 0
    }

    func differs(from current: TrackFields) -> Bool {
        !differences(from: current).isEmpty
    }

    /// 검사 당시와 달라진 항목 이름
    func differences(from current: TrackFields) -> [String] {
        var fields: [String] = []
        let pairs: [(ProposalField, String, String)] = [(.title, title, current.title), (.artist, artist, current.artist),
                                                        (.album, album, current.album), (.albumArtist, albumArtist, current.albumArtist)]
        for (field, then, now) in pairs where Normalizer.compareKey(then) != Normalizer.compareKey(now) {
            fields.append(field.label)
        }
        // 커버는 비교하지 않는다: ITLibrary가 곡에 없는 커버(앨범 캐시)를 있다고 보고하는 경우가 있어
        // 검사 값을 믿을 수 없다(실측 140곡 오판). 커버를 채울지는 쓰기 직전 Music에서 읽은 값으로 정한다.
        return fields
    }

    /// 검사 이후 사용자가 Music에서 '직접' 바꾼 것으로 보이는 항목만 돌려준다 (적용을 막아야 하는 경우).
    /// 검사 값은 ITLibrary, 지금 값은 Music 스크립팅에서 읽어 경로가 달라, 이 앱이 이전에 적용한 변경을
    /// ITLibrary가 늦게 반영하면 멀쩡한 곡도 '달라졌다'고 나온다(특히 앨범 아티스트). 그래서 지금 값이
    /// 이번에 쓰려는 값(proposed)과 같으면 우리가 이전에 적용한 결과로 보고 충돌에서 뺀다
    /// (지금 값 == 쓰려는 값이면 어차피 덮어쓸 게 없어 안전). 지금 값이 둘 다와 다른 '제3의 값'일 때만 막는다.
    func conflicts(with current: TrackFields, proposed: [String: FieldValue]) -> [String] {
        let pairs: [(ProposalField, String, String)] = [(.title, title, current.title), (.artist, artist, current.artist),
                                                        (.album, album, current.album), (.albumArtist, albumArtist, current.albumArtist)]
        return pairs.compactMap { field, scanned, now in
            guard Normalizer.compareKey(scanned) != Normalizer.compareKey(now) else { return nil }
            if case .text(let want)? = proposed[field.rawValue], Normalizer.compareKey(want) == Normalizer.compareKey(now) {
                return nil
            }
            return field.label
        }
    }
}

/// 작업 항목의 계획
public enum ApplyPlan: Codable, Equatable, Sendable {
    /// 제안 적용
    case apply(proposed: [String: FieldValue], artworkCandidates: [String], scanned: ScannedValues)
    /// 다른 작업에서 바꾼 것을 되돌림
    case undo(sourceJobID: Int64)
    /// 사용자가 직접 입력한 값 (기존 값과 달라도 쓴다)
    case override(values: [String: FieldValue], artworkCandidates: [String], scanned: ScannedValues)
}

public enum FieldWritePolicy: String, Codable, CaseIterable, Sendable {
    /// 비어 있거나 플레이스홀더일 때만 채움 (기본)
    case fillEmpty
    /// 현재 값과 다르면 교체 (고급)
    case replaceIfDifferent
    /// 변경 안 함
    case never

    public var label: String {
        switch self {
        case .fillEmpty: return MTMLoc.t("writePolicy.fillEmpty", "비어 있을 때만")
        case .replaceIfDifferent: return MTMLoc.t("writePolicy.replaceIfDifferent", "다르면 교체")
        case .never: return MTMLoc.t("writePolicy.never", "변경 안 함")
        }
    }
}

public struct WritePolicies: Codable, Equatable, Sendable {
    /// 사용자가 기본값과 다르게 고른 정책만 저장한다 (기본값이 바뀌어도 기존 설정이 따라감)
    public var overrides: [String: FieldWritePolicy] = [:]

    /// 기본값: 제목·가수·앨범명은 식별 결과와 다르면 교체(사용자 결정), 나머지는 비어 있을 때만.
    public static let defaults: [ProposalField: FieldWritePolicy] = [
        .title: .replaceIfDifferent, .artist: .replaceIfDifferent, .album: .replaceIfDifferent,
    ]

    public init() {}

    public static func defaultPolicy(for field: ProposalField) -> FieldWritePolicy {
        defaults[field] ?? .fillEmpty
    }

    public func policy(for field: ProposalField) -> FieldWritePolicy {
        overrides[field.rawValue] ?? Self.defaultPolicy(for: field)
    }

    public mutating func set(_ policy: FieldWritePolicy, for field: ProposalField) {
        overrides[field.rawValue] = policy == Self.defaultPolicy(for: field) ? nil : policy
    }

    /// 사용자가 직접 입력한 값: 모든 필드를 다르면 교체
    public static var userOverride: WritePolicies {
        var policies = WritePolicies()
        for field in ProposalField.allCases { policies.set(.replaceIfDifferent, for: field) }
        return policies
    }

    /// 모든 필드를 '비어 있을 때만'으로 (지시서 원래 기본값)
    public static var fillEmptyOnly: WritePolicies {
        var policies = WritePolicies()
        for field in ProposalField.allCases { policies.set(.fillEmpty, for: field) }
        return policies
    }
}

extension TrackFields {
    /// 스캔 값으로 만든 현재 값 (적용 미리보기용)
    public init(_ track: LibraryTrack) {
        self.init()
        title = track.title
        artist = track.artist ?? ""
        album = track.album ?? ""
        albumArtist = track.albumArtist ?? ""
        genre = track.genre ?? ""
        year = track.year
        trackNumber = track.trackNumber
        trackCount = track.trackCount
        discNumber = track.discNumber
        discCount = track.discCount
        artworkCount = track.hasArtwork ? 1 : 0
        location = track.fileURL?.path
    }
}

extension ProposalRecord {
    /// 적용에 쓸 값. 사용자가 적용을 고른 것이므로 식별 결과를 그대로 쓴다
    /// (정확성은 신뢰도 점수로 판단: 기존 값과 핵심 불일치는 -30점, 가수가 바뀌면 자동 적용 금지).
    public func applicableValues(current: LibraryTrack) -> [String: FieldValue] {
        proposedValues
    }

    /// 지금 적용하면 실제로 바뀔 항목과, 하나도 없을 때 그 이유
    /// 확인 결과 쓸 수 없는 커버 후보(이미지 없음·해상도 미달 등)를 뺀 후보. 아직 확인하지 않은 후보는 남긴다.
    public func usableArtworkCandidates(checks: [String: ArtworkCheckRecord], allowLowResolution: Bool) -> [String] {
        artworkCandidates.filter { candidate in
            checks[candidate].map { $0.isUsable(allowLowResolution: allowLowResolution) } ?? true
        }
    }

    public func preview(current: LibraryTrack, rules: CompletenessRules, policies: WritePolicies,
                        artworkChecks: [String: ArtworkCheckRecord] = [:], allowLowResolutionArtwork: Bool = true)
        -> (fields: [ProposalField], reason: String?) {
        let id = PersistentID(hex: persistentID) ?? PersistentID(0)
        let isOverride = decision == .userOverride
        let usableArtwork = usableArtworkCandidates(checks: artworkChecks, allowLowResolution: allowLowResolutionArtwork)
        let (change, wantsArtwork) = ChangePlanner.plan(
            proposed: isOverride ? proposedValues : applicableValues(current: current),
            hasArtworkCandidates: !usableArtwork.isEmpty,
            current: TrackFields(current), id: id, rules: rules, policies: isOverride ? .userOverride : policies,
            caseSensitive: isOverride)
        let fields = change.fields + (wantsArtwork ? [.artwork] : [])
        guard fields.isEmpty else { return (fields, nil) }
        if isOverride { return ([], MTMLoc.t("preview.overrideSame", "입력한 값이 현재 값과 같음")) }
        if confidenceLevel == .none { return ([], MTMLoc.t("preview.identifyFailed", "식별 실패 — 직접 수정해 적용할 수 있습니다")) }
        if !current.hasArtwork, !artworkCandidates.isEmpty, usableArtwork.isEmpty {
            let reasons = artworkCandidates.compactMap { candidate in
                artworkChecks[candidate].map { "\(ArtworkService.sourceLabel(candidate)): \($0.displayReason)" }
            }
            return ([], MTMLoc.f("preview.noCover", "커버 없음 — %@", reasons.joined(separator: "; ")))
        }
        if !current.hasArtwork, artworkCandidates.isEmpty, policies.policy(for: .artwork) != .never {
            let localAlbum = Normalizer.clean(current.album)
            if let album, !localAlbum.isEmpty, Normalizer.similarity(localAlbum, album) < 0.8 {
                return ([], MTMLoc.f("preview.noCoverCandidateDiffAlbum", "커버 후보 없음 — 식별된 앨범(%@)이 로컬 앨범과 다름", album))
            }
            return ([], MTMLoc.t("preview.noCoverCandidate", "커버 후보 없음"))
        }
        return ([], MTMLoc.t("preview.nothingToChange", "바꿀 값 없음 (정책상 유지)"))
    }

    /// 제안된 값 (커버 제외)
    public var proposedValues: [String: FieldValue] {
        var values: [String: FieldValue] = [:]
        func text(_ field: ProposalField, _ value: String?) {
            if let value, !Normalizer.clean(value).isEmpty { values[field.rawValue] = .text(Normalizer.clean(value)) }
        }
        func number(_ field: ProposalField, _ value: Int?) {
            if let value, value > 0 { values[field.rawValue] = .number(value) }
        }
        text(.title, title)
        text(.artist, artist)
        text(.album, album)
        text(.albumArtist, albumArtist)
        text(.genre, genre)
        number(.year, year)
        number(.trackNumber, trackNo)
        number(.trackCount, trackCount)
        number(.discNumber, discNo)
        number(.discCount, discCount)
        return values
    }
}
