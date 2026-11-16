import Foundation

/// 식별 결과 검수표 (CSV). 엑셀·Numbers에서 제안값을 고치거나 결정 열에 승인·거절을 적어 다시 가져온다.
public enum ReviewSheet {
    public static let header = [
        "persistent_id", "결정(승인/거절)", "신뢰도", "점수", "상태",
        "현재 제목", "현재 가수", "현재 앨범",
        "제안 제목", "제안 가수", "제안 앨범", "제안 앨범 아티스트", "제안 장르",
        "제안 연도", "제안 트랙 번호", "제안 트랙 수", "제안 디스크 번호", "제안 디스크 수",
        "근거",
    ]

    /// 검수 대상 열 → 제안 필드 (가져올 때 비교)
    static let editableColumns: [(index: Int, field: ProposalField)] = [
        (8, .title), (9, .artist), (10, .album), (11, .albumArtist), (12, .genre),
        (13, .year), (14, .trackNumber), (15, .trackCount), (16, .discNumber), (17, .discCount),
    ]

    /// ID 앞에 붙이는 접두어. 16진수 ID가 숫자로만 이뤄졌거나 `12E3…` 꼴이면 엑셀이 숫자(지수 표기)로 바꿔
    /// 저장해 버려 다시 가져올 때 곡을 찾지 못한다. 접두어를 붙여 항상 문자열로 남게 한다.
    static let idPrefix = "id:"

    /// 스프레드시트가 수식으로 실행할 수 있는 값(`=`·`+`·`-`·`@`로 시작)은 앞에 `'`를 붙여 글자로 남긴다.
    /// 값은 외부 데이터베이스에서 온 것이므로 그대로 내보내면 수식 주입이 될 수 있다. 가져올 때 다시 뗀다.
    static func guarded(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        return "'" + value
    }

    static func unguarded(_ value: String) -> String {
        guard value.hasPrefix("'"), let second = value.dropFirst().first, "=+-@".contains(second) else { return value }
        return String(value.dropFirst())
    }

    /// - Parameter statuses: 표에 보이는 상태 이름 (persistent_id → 상태)
    public static func export(proposals: [ProposalRecord], tracks: [PersistentID: LibraryTrack],
                              statuses: [String: String] = [:]) -> String {
        var rows = [header]
        for proposal in proposals.sorted(by: { ($0.albumGroupKey, $0.persistentID) < ($1.albumGroupKey, $1.persistentID) }) {
            let track = PersistentID(hex: proposal.persistentID).flatMap { tracks[$0] }
            func number(_ value: Int?) -> String { value.map(String.init) ?? "" }
            rows.append([
                idPrefix + proposal.persistentID, "", proposal.confidenceLevel.label, String(proposal.confidenceScore),
                statuses[proposal.persistentID] ?? "",
                guarded(Normalizer.clean(track?.title)), guarded(Normalizer.clean(track?.artist)), guarded(Normalizer.clean(track?.album)),
                guarded(proposal.title ?? ""), guarded(proposal.artist ?? ""), guarded(proposal.album ?? ""),
                guarded(proposal.albumArtist ?? ""), guarded(proposal.genre ?? ""),
                number(proposal.year), number(proposal.trackNo), number(proposal.trackCount),
                number(proposal.discNo), number(proposal.discCount),
                guarded(proposal.evidence.reasons.joined(separator: ", ")),
            ])
        }
        // BOM: 엑셀에서 한글이 깨지지 않게
        return "\u{FEFF}" + CSV.encode(rows)
    }

    public struct ImportResult: Sendable, Equatable {
        /// 제안값을 고친 곡 → 직접 수정으로 저장할 값
        public var overrides: [PersistentID: [ProposalField: FieldValue]] = [:]
        public var approve: [PersistentID] = []
        public var reject: [PersistentID] = []
        public var unchanged = 0
        public var errors: [String] = []
    }

    public static func parse(_ text: String, proposals: [String: ProposalRecord]) -> ImportResult {
        var result = ImportResult()
        let rows = CSV.decode(text)
        guard let first = rows.first, first.first?.trimmingCharacters(in: .whitespaces) == header[0] else {
            result.errors.append("MusicTag Manager에서 내보낸 검수표가 아닙니다 (첫 줄 머리글이 다름)")
            return result
        }
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard var pidText = row.first?.trimmingCharacters(in: .whitespaces), !pidText.isEmpty else { continue }
            // 접두어가 없는 예전 검수표도 그대로 읽는다
            if pidText.lowercased().hasPrefix(idPrefix) { pidText = String(pidText.dropFirst(idPrefix.count)) }
            guard let id = PersistentID(hex: pidText), let proposal = proposals[id.hex] else {
                result.errors.append("\(line)행: 알 수 없는 곡 (\(pidText))")
                continue
            }
            func cell(_ index: Int) -> String { index < row.count ? unguarded(Normalizer.clean(row[index])) : "" }

            var values: [ProposalField: FieldValue] = [:]
            var edited = false
            var invalid = false
            for (index, field) in editableColumns {
                let text = cell(index)
                if ChangePlanner.numberFields.contains(field) {
                    let number = text.isEmpty ? 0 : Int(text)
                    guard let number else {
                        result.errors.append("\(line)행: ‘\(header[index])’에 숫자가 아닌 값 (\(text))")
                        invalid = true
                        continue
                    }
                    values[field] = .number(number)
                    if number != (proposedNumber(proposal, field) ?? 0) { edited = true }
                } else {
                    values[field] = .text(text)
                    if Normalizer.compareKey(text) != Normalizer.compareKey(proposedText(proposal, field)) { edited = true }
                }
            }
            if invalid { continue }
            if edited { result.overrides[id] = values }

            switch cell(1).lowercased() {
            case "승인", "approve", "o", "y", "yes": result.approve.append(id)
            case "거절", "reject", "x", "n", "no": result.reject.append(id)
            case "": if !edited { result.unchanged += 1 }
            default: result.errors.append("\(line)행: 결정 열은 ‘승인’ 또는 ‘거절’만 쓸 수 있습니다 (\(cell(1)))")
            }
        }
        return result
    }

    static func proposedText(_ proposal: ProposalRecord, _ field: ProposalField) -> String? {
        switch field {
        case .title: return proposal.title
        case .artist: return proposal.artist
        case .album: return proposal.album
        case .albumArtist: return proposal.albumArtist
        case .genre: return proposal.genre
        default: return nil
        }
    }

    static func proposedNumber(_ proposal: ProposalRecord, _ field: ProposalField) -> Int? {
        switch field {
        case .year: return proposal.year
        case .trackNumber: return proposal.trackNo
        case .trackCount: return proposal.trackCount
        case .discNumber: return proposal.discNo
        case .discCount: return proposal.discCount
        default: return nil
        }
    }
}
