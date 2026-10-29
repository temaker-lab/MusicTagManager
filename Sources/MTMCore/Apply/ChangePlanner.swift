import Foundation

/// 제안값 + Music의 현재 값 + 필드별 정책 → 실제로 쓸 변경
public enum ChangePlanner {
    public static let textFields: [ProposalField] = [.title, .artist, .album, .albumArtist, .genre]
    public static let numberFields: [ProposalField] = [.year, .trackNumber, .trackCount, .discNumber, .discCount]

    /// - Returns: 텍스트·숫자 변경, 그리고 커버를 넣어야 하는지
    /// - Parameter caseSensitive: 사용자가 직접 입력한 값(직접 수정)일 때만 true. 대소문자·문장부호만 바뀐 값도 쓰도록
    ///   정확 비교(clean)를 쓴다. 식별 결과는 false로 두어 compareKey로 비교(철자·악센트만 다른 겉모양 변경은 쓰지 않음).
    public static func plan(proposed: [String: FieldValue], hasArtworkCandidates: Bool, current: TrackFields,
                            id: PersistentID, rules: CompletenessRules, policies: WritePolicies,
                            caseSensitive: Bool = false) -> (change: TrackChange, wantsArtwork: Bool) {
        // 필수 3개 텍스트 항목은 완비 판정과 같은 기준(플레이스홀더 = 빈 값)으로 비었는지 본다
        let missing = Set(CompletenessChecker(rules: rules).missingFields(of: current.libraryTrack(id: id)))
        var change = TrackChange()

        for field in textFields {
            guard case .text(let proposedValue)? = proposed[field.rawValue], case .text(let currentValue)? = current.value(of: field) else { continue }
            let isEmpty = RequiredField(rawValue: field.rawValue).map(missing.contains) ?? Normalizer.clean(currentValue).isEmpty
            let same = caseSensitive
                ? Normalizer.clean(currentValue) == Normalizer.clean(proposedValue)
                : Normalizer.compareKey(currentValue) == Normalizer.compareKey(proposedValue)
            if shouldWrite(policies.policy(for: field), isEmpty: isEmpty, same: same) {
                change.values[field.rawValue] = .text(proposedValue)
            }
        }
        for field in numberFields {
            guard case .number(let proposedValue)? = proposed[field.rawValue], case .number(let currentValue)? = current.value(of: field) else { continue }
            if shouldWrite(policies.policy(for: field), isEmpty: currentValue <= 0, same: currentValue == proposedValue) {
                change.values[field.rawValue] = .number(proposedValue)
            }
        }
        dropInconsistentNumbering(&change, proposed: proposed, current: current)
        let wantsArtwork: Bool
        switch policies.policy(for: .artwork) {
        case .fillEmpty: wantsArtwork = hasArtworkCandidates && current.artworkCount == 0
        case .replaceIfDifferent: wantsArtwork = hasArtworkCandidates
        case .never: wantsArtwork = false
        }
        return (change, wantsArtwork)
    }

    /// 트랙·디스크 번호 체계가 다른 릴리스의 값은 섞지 않는다.
    /// - 기존 트랙(디스크) 번호와 제안 번호가 다르면 다른 판이므로 트랙 수·디스크 정보를 쓰지 않는다.
    /// - 트랙 수 < 트랙 번호, 디스크 수 < 디스크 번호는 Music이 조용히 무시하므로(Phase 3 실측) 쓰지 않는다.
    static func dropInconsistentNumbering(_ change: inout TrackChange, proposed: [String: FieldValue], current: TrackFields) {
        func number(_ field: ProposalField) -> Int? {
            if case .number(let value)? = proposed[field.rawValue] { return value }
            return nil
        }
        if current.trackNumber > 0, let proposedTrack = number(.trackNumber), proposedTrack != current.trackNumber {
            for field in [ProposalField.trackCount, .discNumber, .discCount] { change.values[field.rawValue] = nil }
        }
        if current.discNumber > 0, let proposedDisc = number(.discNumber), proposedDisc != current.discNumber {
            for field in [ProposalField.trackNumber, .trackCount, .discCount] { change.values[field.rawValue] = nil }
        }
        let finalTrack: Int
        if case .number(let value)? = change.values[ProposalField.trackNumber.rawValue] { finalTrack = value } else { finalTrack = current.trackNumber }
        if case .number(let count)? = change.values[ProposalField.trackCount.rawValue], count < finalTrack {
            change.values[ProposalField.trackCount.rawValue] = nil
        }
        let finalDisc: Int
        if case .number(let value)? = change.values[ProposalField.discNumber.rawValue] { finalDisc = value } else { finalDisc = current.discNumber }
        if case .number(let count)? = change.values[ProposalField.discCount.rawValue], count < finalDisc {
            change.values[ProposalField.discCount.rawValue] = nil
        }
    }

    static func shouldWrite(_ policy: FieldWritePolicy, isEmpty: Bool, same: Bool) -> Bool {
        guard !same else { return false }
        switch policy {
        case .fillEmpty: return isEmpty
        case .replaceIfDifferent: return true
        case .never: return false
        }
    }
}
