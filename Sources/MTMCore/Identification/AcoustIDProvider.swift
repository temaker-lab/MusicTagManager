import AVFoundation
import CoreMedia
import Foundation

public struct AudioFingerprint: Sendable, Hashable {
    public var durationSeconds: Int
    public var fingerprint: String
}

public struct FingerprintMatch: Sendable, Hashable {
    public var recordingID: String
    public var score: Double
    /// AcoustID가 함께 돌려준 MusicBrainz 녹음 정보 (제목·가수·수록 릴리스). 있으면 MusicBrainz 조회를 생략한다.
    public var recording: RecordingCandidate?
}

/// AcoustID + Chromaprint(fpcalc). API 키나 fpcalc가 없으면 만들어지지 않는다(자동 비활성).
public final class AcoustIDProvider: Sendable {
    public static let keychainService = "MusicTagManager.AcoustID"
    public static let keychainAccount = "default"
    /// 앱에 내장된 공용 AcoustID 키 (무료 배포용). 사용자가 설정에서 자기 키를 넣으면 그 키가 우선한다.
    /// 무료 앱이라 키 노출을 감수한다. 공란이면 내장 키 없이 사용자 키에만 의존한다.
    public static let defaultAPIKey = "YiKWEpWSEt"

    private let http: HTTPClient
    private let apiKey: String
    private let fpcalc: URL
    private let limiter: RateLimiter

    public init(http: HTTPClient, apiKey: String, fpcalc: URL, limiter: RateLimiter = RateLimiter(interval: 0.34)) {
        self.http = http
        self.apiKey = apiKey
        self.fpcalc = fpcalc
        self.limiter = limiter
    }

    /// 사용자 키(키체인) 우선, 없으면 내장 공용 키를 쓴다. 키도 없고 fpcalc도 없으면 비활성.
    public static func makeIfConfigured(http: HTTPClient) -> AcoustIDProvider? {
        let userKey = KeychainStore.read(service: keychainService, account: keychainAccount) ?? ""
        let key = userKey.isEmpty ? defaultAPIKey : userKey
        guard !key.isEmpty else {
            Log.identify.info("AcoustID 키 없음 → 지문 식별 비활성")
            return nil
        }
        guard let fpcalc = FpcalcLocator.locate() else {
            Log.identify.error("fpcalc를 찾을 수 없음 → 지문 식별 비활성")
            return nil
        }
        return AcoustIDProvider(http: http, apiKey: key, fpcalc: fpcalc)
    }

    /// 앞 120초로 지문 생성 (곡당 약 0.1초).
    /// ① fpcalc 직접(FFmpeg) → ② AVAudioFile로 디코드한 WAV → ③ AVAssetReader(재생 경로)로 디코드한 WAV 순으로,
    /// 빈 지문이면 실패로 보고 다음 단계로 넘어간다. Music에서 재생되는 파일이면 보통 ②·③에서 지문이 나온다.
    public func fingerprint(of file: URL) async throws -> AudioFingerprint {
        var firstError: Error?
        do {
            let direct = try await runFpcalc(path: file.path)
            if !direct.fingerprint.isEmpty { return direct }
            firstError = ProcessRunner.Failure(status: 0, message: "빈 지문")
        } catch {
            firstError = error
        }
        // FFmpeg가 못 읽거나 빈 지문 → CoreAudio로 디코드한 WAV로 재시도
        for decode in [Self.decodeWithAudioFile, Self.decodeWithAssetReader] {
            guard let wav = try? await decode(file, 120) else { continue }
            defer { try? FileManager.default.removeItem(at: wav) }
            if let result = try? await runFpcalc(path: wav.path), !result.fingerprint.isEmpty {
                return result
            }
        }
        throw firstError ?? ProcessRunner.Failure(status: -1, message: "오디오에서 지문을 만들지 못했습니다")
    }

    private func runFpcalc(path: String) async throws -> AudioFingerprint {
        let output = try await ProcessRunner.run(fpcalc, arguments: ["-json", "-length", "120", path])
        struct Output: Decodable { let duration: Double; let fingerprint: String }
        let decoded = try JSONDecoder().decode(Output.self, from: output)
        return AudioFingerprint(durationSeconds: Int(decoded.duration.rounded()), fingerprint: decoded.fingerprint)
    }

    /// AVAudioFile(ExtAudioFile)로 앞 maxSeconds초를 16-bit PCM WAV로 디코드한다.
    /// AVAudioFile의 처리 포맷은 항상 float32라 읽기·쓰기 버퍼 포맷이 같아 그대로 넘긴다(파일에 쓸 때 16-bit로 인코딩).
    static func decodeWithAudioFile(_ source: URL, maxSeconds: Double) async throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let outFile = try AVAudioFile(forWriting: output, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else {
            throw ProcessRunner.Failure(status: -1, message: "PCM 버퍼 생성 실패")
        }
        var remaining = AVAudioFramePosition((maxSeconds * format.sampleRate).rounded())
        while remaining > 0 {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try outFile.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        return output
    }

    /// AVAssetReader(Music 재생과 같은 디코드 경로)로 앞 maxSeconds초를 16-bit PCM으로 읽어 WAV로 쓴다.
    /// AVAudioFile이 못 여는 컨테이너(멀티트랙 M4A 등)도 여기서 열리는 경우가 많다.
    static func decodeWithAssetReader(_ source: URL, maxSeconds: Double) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ProcessRunner.Failure(status: -1, message: "오디오 트랙 없음")
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        let sampleRate = 44_100, channels = 2, bits = 16
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { throw ProcessRunner.Failure(status: -1, message: "리더 출력 추가 실패") }
        reader.add(trackOutput)
        guard reader.startReading() else {
            throw reader.error ?? ProcessRunner.Failure(status: -1, message: "오디오 읽기 실패")
        }
        var pcm = Data()
        while reader.status == .reading, let sample = trackOutput.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sample) {
                let length = CMBlockBufferGetDataLength(block)
                var chunk = Data(count: length)
                chunk.withUnsafeMutableBytes { raw in
                    if let base = raw.baseAddress {
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                    }
                }
                pcm.append(chunk)
            }
            CMSampleBufferInvalidate(sample)
        }
        guard reader.status == .completed || !pcm.isEmpty, !pcm.isEmpty else {
            throw reader.error ?? ProcessRunner.Failure(status: -1, message: "오디오 디코드 실패")
        }
        return try writeWAV(pcm: pcm, sampleRate: sampleRate, channels: channels, bits: bits)
    }

    /// 16-bit PCM 바이트에 WAV 헤더(44바이트)를 붙여 임시 파일로 쓴다.
    static func writeWAV(pcm: Data, sampleRate: Int, channels: Int, bits: Int) throws -> URL {
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        var header = Data()
        func append(_ string: String) { header.append(contentsOf: string.utf8) }
        func append32(_ value: Int) { var v = UInt32(truncatingIfNeeded: value).littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func append16(_ value: Int) { var v = UInt16(truncatingIfNeeded: value).littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + pcm.count); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(channels)
        append32(sampleRate); append32(byteRate); append16(blockAlign); append16(bits)
        append("data"); append32(pcm.count)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try (header + pcm).write(to: url, options: .atomic)
        return url
    }

    public func lookup(_ fingerprint: AudioFingerprint) async throws -> [FingerprintMatch] {
        var request = URLRequest(url: URL(string: "https://api.acoustid.org/v2/lookup")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client", value: apiKey),
            URLQueryItem(name: "duration", value: String(fingerprint.durationSeconds)),
            URLQueryItem(name: "fingerprint", value: fingerprint.fingerprint),
            URLQueryItem(name: "meta", value: "recordings releasegroups releases tracks compress"),
        ]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        // API 키가 캐시 키에 남지 않도록 지문 해시로 캐시
        let cacheKey = "acoustid-meta:\(fingerprint.durationSeconds):\(Self.hash(fingerprint.fingerprint))"
        let data = try await http.data(for: request, provider: ProviderID.acoustid.rawValue, limiter: limiter, cacheKey: cacheKey)
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [FingerprintMatch] {
        let response = try JSONDecoder().decode(AcoustIDResponse.self, from: data)
        guard response.status == "ok" else {
            throw NSError(domain: "AcoustID", code: 1, userInfo: [NSLocalizedDescriptionKey: response.error?.message ?? "AcoustID 오류"])
        }
        var seen = Set<String>()
        return (response.results ?? []).sorted { $0.score > $1.score }.flatMap { result in
            (result.recordings ?? []).compactMap { recording in
                guard seen.insert(recording.id).inserted else { return nil }
                return FingerprintMatch(recordingID: recording.id, score: result.score, recording: candidate(from: recording))
            }
        }
    }

    /// 메타데이터가 붙은 녹음만 후보로 만든다 (ID만 온 경우 nil → MusicBrainz에서 조회)
    static func candidate(from recording: AcoustIDResponse.Recording) -> RecordingCandidate? {
        guard let title = recording.title, let groups = recording.releasegroups else { return nil }
        let artists = recording.artists ?? []
        let artistName = artists.map { $0.name + ($0.joinphrase ?? "") }.joined()
        var appearances: [RecordingCandidate.Appearance] = []
        for group in groups {
            for release in group.releases ?? [] {
                guard let medium = release.mediums?.first, let track = medium.tracks?.first else { continue }
                let date = release.date.map { date in
                    [date.year.map { String(format: "%04d", $0) }, date.month.map { String(format: "%02d", $0) },
                     date.day.map { String(format: "%02d", $0) }].compactMap { $0 }.joined(separator: "-")
                }
                let candidate = ReleaseCandidate(
                    source: .musicbrainz, id: release.id, releaseGroupID: group.id, title: release.title ?? group.title ?? "",
                    artist: (group.artists ?? artists).map { $0.name + ($0.joinphrase ?? "") }.joined(),
                    artistIDs: (group.artists ?? artists).map(\.id), date: date, primaryType: group.type,
                    secondaryTypes: group.secondarytypes ?? [], trackCount: release.trackCount ?? 0,
                    discCount: release.mediumCount ?? 1)
                appearances.append(RecordingCandidate.Appearance(release: candidate, discNumber: medium.position ?? 1,
                                                                 trackNumber: track.position ?? 0))
            }
        }
        return RecordingCandidate(source: .musicbrainz, id: recording.id, title: title, artist: artistName,
                                  artistIDs: artists.map(\.id), durationMs: recording.duration.map { Int($0 * 1000) },
                                  isrc: nil, appearances: appearances)
    }

    static func hash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

struct AcoustIDResponse: Decodable {
    struct ErrorInfo: Decodable { let message: String }
    struct Artist: Decodable { let id: String; let name: String; let joinphrase: String? }
    struct DateParts: Decodable { let year: Int?; let month: Int?; let day: Int? }
    struct Track: Decodable { let position: Int? }
    struct Medium: Decodable { let position: Int?; let tracks: [Track]? }
    struct Release: Decodable {
        let id: String
        let title: String?
        let date: DateParts?
        let trackCount: Int?
        let mediumCount: Int?
        let mediums: [Medium]?
        enum CodingKeys: String, CodingKey {
            case id, title, date, mediums
            case trackCount = "track_count"
            case mediumCount = "medium_count"
        }
    }
    struct ReleaseGroup: Decodable {
        let id: String
        let title: String?
        let type: String?
        let secondarytypes: [String]?
        let artists: [Artist]?
        let releases: [Release]?
    }
    struct Recording: Decodable {
        let id: String
        let title: String?
        let duration: Double?
        let artists: [Artist]?
        let releasegroups: [ReleaseGroup]?
    }
    struct Result: Decodable {
        let score: Double
        let recordings: [Recording]?
    }
    let status: String
    let results: [Result]?
    let error: ErrorInfo?
}

/// 번들 안의 fpcalc (공식 단독 바이너리 v1.6.1, LGPL)
public enum FpcalcLocator {
    public static func locate() -> URL? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["MTM_FPCALC"] { candidates.append(URL(fileURLWithPath: path)) }
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("bin/fpcalc")) }
        // 개발 중 `swift run`: 패키지 루트의 Resources/bin
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/bin/fpcalc"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

enum ProcessRunner {
    struct Failure: LocalizedError {
        let status: Int32
        let message: String
        var errorDescription: String? { "외부 도구 실패 (\(status)): \(message)" }
    }

    static func run(_ executable: URL, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: Failure(status: process.terminationStatus, message: message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// 키체인 일반 암호. Developer ID 없이 ad-hoc 서명하는 앱은 빌드할 때마다 서명이 바뀌어
/// Security API로 읽으면 매번 접근 허용 창이 뜬다. 그래서 시스템 `security` 도구로 읽고 쓴다.
public enum KeychainStore {
    private static let tool = URL(fileURLWithPath: "/usr/bin/security")

    public static func read(service: String, account: String) -> String? {
        guard let output = try? runSync(["find-generic-password", "-s", service, "-a", account, "-w"]) else { return nil }
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func write(_ value: String, service: String, account: String) throws {
        _ = try runSync(["add-generic-password", "-U", "-s", service, "-a", account, "-w", value])
    }

    public static func delete(service: String, account: String) {
        _ = try? runSync(["delete-generic-password", "-s", service, "-a", account])
    }

    private static func runSync(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProcessRunner.Failure(status: process.terminationStatus, message: "security \(arguments.first ?? "")")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
