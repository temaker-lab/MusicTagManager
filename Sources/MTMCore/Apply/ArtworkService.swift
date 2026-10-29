import CoreGraphics
import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers

public struct PreparedArtwork: Sendable, Equatable {
    public let file: URL
    public let width: Int
    public let height: Int
    /// 사용한 후보 (`track:` · `itunes:` · `caa:`)
    public let source: String
}

public enum ArtworkError: LocalizedError, Equatable {
    case notImage
    case tooSmall(Int, Int)
    case notSquare(Int, Int)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .notImage: return MTMLoc.t("art.err.notImage", "이미지가 아닙니다")
        case .tooSmall(let w, let h): return MTMLoc.f("art.err.tooSmall", "해상도가 낮습니다 (%d×%d)", w, h)
        case .notSquare(let w, let h): return MTMLoc.f("art.err.notSquare", "정사각형이 아닙니다 (%d×%d)", w, h)
        case .unavailable: return MTMLoc.t("art.err.unavailable", "커버를 가져올 수 없습니다")
        }
    }
}

public struct ArtworkPreparation: Sendable {
    public var prepared: PreparedArtwork?
    /// 쓰지 못한 후보와 이유 (예: "Cover Art Archive: 해상도가 낮습니다 (400×396)")
    public var failures: [String]

    public var failureSummary: String { failures.joined(separator: "; ") }
}

/// 커버 후보를 순서대로 시도해 첫 번째로 쓸 수 있는 이미지를 준비한다.
/// 같은 후보는 한 번만 내려받는다 (같은 앨범의 곡들이 공유).
/// 기준 해상도(600px) 후보가 하나도 없으면 `lowResolutionMinimum` 이상도 허용한다
/// (Phase 3 실측: Cover Art Archive 커버는 400~500px가 많다).
public final class ArtworkService: Sendable {
    private let directory: URL
    private let music: MusicScripting
    private let http: HTTPClient
    private let limiter: RateLimiter
    private let minimumSide: Int
    private let lowResolutionMinimum: Int?
    private let maximumSide: Int
    private let downloads = DownloadMemo()
    private let checks = CheckMemo()
    private let checkStore: ArtworkCheckStore?
    /// `itunes-song:` 지연 후보를 풀 때 쓰는 iTunes 검색기 (없으면 그 후보는 건너뛴다)
    private let itunes: ITunesSearchProvider?

    public init(directory: URL, music: MusicScripting, http: HTTPClient = HTTPClient(cache: nil),
                limiter: RateLimiter = RateLimiter(interval: 0.5), minimumSide: Int = 600,
                lowResolutionMinimum: Int? = 300, maximumSide: Int = 1200, checkStore: ArtworkCheckStore? = nil,
                itunes: ITunesSearchProvider? = nil) {
        self.checkStore = checkStore
        self.directory = directory
        self.music = music
        self.http = http
        self.limiter = limiter
        self.minimumSide = minimumSide
        self.lowResolutionMinimum = lowResolutionMinimum
        self.maximumSide = maximumSide
        self.itunes = itunes
    }

    public func prepare(_ candidates: [String]) async -> PreparedArtwork? {
        await prepareWithReport(candidates).prepared
    }

    /// 후보를 순서대로 확인한다. 600px 이상이면 바로 쓰고, 없으면 처음 찾은 저해상도(`lowResolutionMinimum` 이상) 후보를 쓴다.
    /// 확인한 결과는 `checkStore`에 남겨 적용 전 미리보기에서 쓸 수 없는 후보를 빼는 데 쓴다.
    public func prepareWithReport(_ candidates: [String]) async -> ArtworkPreparation {
        var failures: [String] = []
        var fallback: (candidate: String, image: ProcessedArtwork)?
        let floor = min(lowResolutionMinimum ?? minimumSide, minimumSide)
        for candidate in candidates {
            if Task.isCancelled { break }
            switch await check(candidate, floor: floor) {
            case .usable(let image):
                let trusted = Self.isTrusted(candidate)
                if trusted || min(image.width, image.height) >= minimumSide {
                    return await finish(candidate, image, failures: failures)
                }
                if fallback == nil { fallback = (candidate, image) }
            case .unusable(let reason):
                let line = "\(Self.sourceLabel(candidate)): \(reason)"
                if !failures.contains(line) { failures.append(line) }
            case .offline:
                return ArtworkPreparation(prepared: nil, failures: failures + [MTMLoc.t("art.fail.offline", "네트워크 연결 없음")])
            }
        }
        if let fallback { return await finish(fallback.candidate, fallback.image, failures: failures) }
        return ArtworkPreparation(prepared: nil, failures: failures)
    }

    struct ProcessedArtwork: Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    enum CheckOutcome: Sendable {
        case usable(ProcessedArtwork)
        case unusable(String)
        case offline
    }

    /// 사용자가 고른 파일·같은 앨범 곡의 커버는 해상도·비율과 관계없이 쓴다
    public static func isTrusted(_ candidate: String) -> Bool {
        candidate.hasPrefix("track:") || candidate.hasPrefix("file:")
    }

    private func check(_ candidate: String, floor: Int) async -> CheckOutcome {
        let key = "\(floor):\(candidate)"
        if let cached = await checks.get(key) { return cached }
        let outcome: CheckOutcome
        do {
            let data = try await download(candidate)
            let processed = try Self.process(data, minimumSide: Self.isTrusted(candidate) ? nil : floor,
                                             maximumSide: maximumSide, requireSquare: !candidate.hasPrefix("file:"))
            outcome = .usable(ProcessedArtwork(data: processed.data, width: processed.width, height: processed.height))
            try? checkStore?.recordArtworkCheck(candidate: candidate, usable: true, width: processed.width,
                                                height: processed.height, reason: nil)
        } catch let error as HTTPError where error == .offline {
            return .offline
        } catch {
            Log.apply.info("커버 후보 제외 \(candidate, privacy: .public): \(error.localizedDescription, privacy: .public)")
            outcome = .unusable(Self.describe(error))
            var size: (Int, Int)?
            if case ArtworkError.tooSmall(let w, let h) = error { size = (w, h) }
            if case ArtworkError.notSquare(let w, let h) = error { size = (w, h) }
            // 저장은 언어 독립적인 한국어 고정 사유로 (표시할 때 displayReason에서 현재 언어로 바꾼다)
            try? checkStore?.recordArtworkCheck(candidate: candidate, usable: false, width: size?.0, height: size?.1,
                                                reason: Self.canonicalReason(error))
        }
        await checks.set(key, outcome)
        return outcome
    }

    private func finish(_ candidate: String, _ image: ProcessedArtwork, failures: [String]) async -> ArtworkPreparation {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(AcoustIDProvider.hash(candidate)).jpg")
            if !FileManager.default.fileExists(atPath: file.path) {
                try image.data.write(to: file, options: .atomic)
            }
            return ArtworkPreparation(
                prepared: PreparedArtwork(file: file, width: image.width, height: image.height, source: candidate), failures: failures)
        } catch {
            return ArtworkPreparation(prepared: nil, failures: failures + [MTMLoc.f("art.fail.saveFailed", "커버 파일 저장 실패: %@", error.localizedDescription)])
        }
    }

    public static func sourceLabel(_ candidate: String) -> String {
        if candidate.hasPrefix("track:") { return MTMLoc.t("art.src.sameAlbum", "같은 앨범 곡") }
        if candidate.hasPrefix("itunes:") || candidate.hasPrefix("itunes-song:") { return "iTunes" }
        if candidate.hasPrefix("file:") { return MTMLoc.t("art.src.selectedFile", "선택한 파일") }
        return candidate.contains("/release-group/") ? MTMLoc.t("art.src.caaRep", "Cover Art Archive(대표)") : "Cover Art Archive"
    }

    static func describe(_ error: Error) -> String {
        if case HTTPError.status(404) = error { return MTMLoc.t("art.noCover", "커버 없음") }
        return error.localizedDescription
    }

    /// DB에 저장하는 안정적인 사유(한국어 고정). 표시할 때 `localizeCheckReason`으로 현재 언어로 바꾼다.
    static func canonicalReason(_ error: Error) -> String {
        if case HTTPError.status(404) = error { return "커버 없음" }
        switch error {
        case ArtworkError.notImage: return "이미지가 아닙니다"
        case ArtworkError.tooSmall(let w, let h): return "해상도가 낮습니다 (\(w)×\(h))"
        case ArtworkError.notSquare(let w, let h): return "정사각형이 아닙니다 (\(w)×\(h))"
        case ArtworkError.unavailable: return "커버를 가져올 수 없습니다"
        default: return error.localizedDescription
        }
    }

    /// DB에 저장된 한국어 고정 사유를 현재 언어로 바꾼다 (레거시 데이터 포함, 치수 꼬리표는 유지).
    static func localizeCheckReason(_ reason: String) -> String {
        for (ko, key) in [("정사각형이 아닙니다", "art.err.notSquareLabel"), ("해상도가 낮습니다", "art.err.tooSmallLabel")]
        where reason.hasPrefix(ko) {
            return MTMLoc.t(key, ko) + String(reason.dropFirst(ko.count))
        }
        switch reason {
        case "커버 없음": return MTMLoc.t("art.noCover", "커버 없음")
        case "이미지가 아닙니다": return MTMLoc.t("art.err.notImage", "이미지가 아닙니다")
        case "커버를 가져올 수 없습니다": return MTMLoc.t("art.err.unavailable", "커버를 가져올 수 없습니다")
        default: return reason
        }
    }

    /// 내려받은 원본은 기억해 두고 해상도 기준만 바꿔 다시 판정한다
    private func download(_ candidate: String) async throws -> Data {
        if let cached = await downloads.get(candidate) {
            guard let data = cached else { throw ArtworkError.unavailable }
            return data
        }
        do {
            let data = try await fetch(candidate)
            await downloads.set(candidate, data)
            return data
        } catch let error as HTTPError where error == .offline {
            throw error
        } catch {
            await downloads.set(candidate, nil)
            throw error
        }
    }

    private func fetch(_ candidate: String) async throws -> Data {
        if candidate.hasPrefix("track:") {
            guard let id = PersistentID(hex: String(candidate.dropFirst(6))),
                  let data = try await music.artworkData(of: id) else { throw ArtworkError.unavailable }
            return data
        }
        if candidate.hasPrefix("file:") {
            return try Data(contentsOf: URL(fileURLWithPath: String(candidate.dropFirst(5))))
        }
        // 지연 후보: 앞 후보들이 모두 실패해 여기까지 왔을 때만 iTunes 노래 검색을 수행한다 (대량 식별 비용 회피)
        if candidate.hasPrefix("itunes-song:") {
            guard let itunes else { throw ArtworkError.unavailable }
            let payload = String(candidate.dropFirst("itunes-song:".count))
            let parts = payload.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            let title = parts.first.map(String.init) ?? ""
            let artist = parts.count > 1 ? String(parts[1]) : ""
            guard !title.isEmpty, let url = try await itunes.songCoverURL(title: title, artist: artist) else {
                throw ArtworkError.unavailable
            }
            var request = URLRequest(url: url)
            request.setValue("MusicTagManager/0.1", forHTTPHeaderField: "User-Agent")
            return try await http.data(for: request, provider: "artwork", limiter: limiter)
        }
        guard let colon = candidate.firstIndex(of: ":"), let url = URL(string: String(candidate[candidate.index(after: colon)...])) else {
            throw ArtworkError.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("MusicTagManager/0.1", forHTTPHeaderField: "User-Agent")
        return try await http.data(for: request, provider: "artwork", limiter: limiter)
    }

    /// 실제 이미지인지·정사각형인지·최소 해상도를 확인하고, 최대 해상도로 줄여 JPEG(품질 0.9)로 만든다.
    public static func process(_ data: Data, minimumSide: Int?, maximumSide: Int = 1200,
                               requireSquare: Bool = true) throws -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw ArtworkError.notImage }
        if let minimumSide, min(width, height) < minimumSide { throw ArtworkError.tooSmall(width, height) }
        // 정사각형(±10%)으로 보거나, 짧은 변이 600px 이상이면서 3:4(가로세로 비 0.75) 이내면 커버로 쓴다
        if requireSquare {
            let ratio = Double(min(width, height)) / Double(max(width, height))
            let acceptable = ratio >= 0.9 || (ratio >= 0.75 && min(width, height) >= 600)
            if !acceptable { throw ArtworkError.notSquare(width, height) }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumSide, max(width, height)),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ArtworkError.notImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ArtworkError.notImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkError.notImage }
        return (output as Data, image.width, image.height)
    }
}

actor DownloadMemo {
    private var values: [String: Data?] = [:]

    func get(_ key: String) -> Data?? { values[key] }
    func set(_ key: String, _ value: Data?) { values[key] = value }
}

actor CheckMemo {
    private var values: [String: ArtworkService.CheckOutcome] = [:]

    func get(_ key: String) -> ArtworkService.CheckOutcome? { values[key] }
    func set(_ key: String, _ value: ArtworkService.CheckOutcome) { values[key] = value }
}

/// 커버 후보 확인 결과 저장소 (적용 전 미리보기에서 쓸 수 없는 후보를 빼기 위함)
public protocol ArtworkCheckStore: Sendable {
    func recordArtworkCheck(candidate: String, usable: Bool, width: Int?, height: Int?, reason: String?) throws
}

public struct ArtworkCheckRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "artwork_checks"

    public var candidate: String
    public var usable: Bool
    public var width: Int?
    public var height: Int?
    public var reason: String?
    public var checkedAt: Date

    enum CodingKeys: String, CodingKey {
        case candidate, usable, width, height, reason
        case checkedAt = "checked_at"
    }

    /// 이 후보를 지금 설정으로 쓸 수 있는가
    public func isUsable(allowLowResolution: Bool, minimumSide: Int = 600) -> Bool {
        guard usable else { return false }
        if ArtworkService.isTrusted(candidate) || allowLowResolution { return true }
        return min(width ?? 0, height ?? 0) >= minimumSide
    }

    public var displayReason: String {
        if usable, let width, let height { return MTMLoc.f("art.err.tooSmall", "해상도가 낮습니다 (%d×%d)", width, height) }
        guard let reason, !reason.isEmpty else { return MTMLoc.t("art.check.unusable", "쓸 수 없음") }
        return ArtworkService.localizeCheckReason(reason)
    }
}

extension AppDatabase: ArtworkCheckStore {
    public func recordArtworkCheck(candidate: String, usable: Bool, width: Int?, height: Int?, reason: String?) throws {
        try writer.write { db in
            try ArtworkCheckRecord(candidate: candidate, usable: usable, width: width, height: height, reason: reason,
                                   checkedAt: Date()).upsert(db)
        }
    }

    public func artworkChecks() throws -> [String: ArtworkCheckRecord] {
        try writer.read { db in
            Dictionary(uniqueKeysWithValues: try ArtworkCheckRecord.fetchAll(db).map { ($0.candidate, $0) })
        }
    }
}
