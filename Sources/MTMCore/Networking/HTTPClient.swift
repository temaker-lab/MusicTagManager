import Foundation

public enum HTTPError: LocalizedError, Equatable {
    case status(Int)
    case offline
    case retriesExhausted(Int)

    public var errorDescription: String? {
        switch self {
        case .status(let code): return "서버 응답 오류 (HTTP \(code))"
        case .offline: return "네트워크에 연결되어 있지 않습니다"
        case .retriesExhausted(let code): return "재시도 후에도 요청이 거절되었습니다 (HTTP \(code))"
        }
    }
}

/// 외부 API 호출 공통: 레이트 리밋, 지수 백오프 재시도, 응답 캐시
public final class HTTPClient: Sendable {
    private let session: URLSession
    private let cache: ResponseCache?
    private let maxAttempts: Int
    private let baseBackoff: TimeInterval

    public init(session: URLSession? = nil, cache: ResponseCache?, maxAttempts: Int = 4, baseBackoff: TimeInterval = 2) {
        self.session = session ?? Self.makeSession()
        self.cache = cache
        self.maxAttempts = maxAttempts
        self.baseBackoff = baseBackoff
    }

    /// 요청 타임아웃은 기본값(60초)로 둔다. 더 짧게 잡았더니 느린 Cover Art Archive 커버 확인이 끊겨
    /// 멀쩡한 커버가 '쓸 수 없음'으로 기록되는 문제가 있었다. 전체 리소스 시간만 넉넉히 제한해 무한 대기만 막는다.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    /// - Parameters:
    ///   - cacheKey: 캐시 키 (기본: URL). POST처럼 URL만으로 구분되지 않으면 직접 지정
    ///   - retryStatuses: 일시적 거절로 보고 재시도할 상태 코드
    public func data(for request: URLRequest, provider: String, limiter: RateLimiter, cacheKey: String? = nil,
                     cacheTTL: TimeInterval = 30 * 86_400, retryStatuses: Set<Int> = [429, 500, 502, 503, 504]) async throws -> Data {
        let key = cacheKey ?? request.url?.absoluteString ?? ""
        if let cache, let cached = try? cache.get(key, maxAge: cacheTTL) {
            return cached
        }
        var lastStatus = 0
        for attempt in 0..<maxAttempts {
            await limiter.acquire()
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    try? cache?.put(key, provider: provider, data: data)
                    return data
                }
                guard retryStatuses.contains(status) else { throw HTTPError.status(status) }
                lastStatus = status
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                // 서버가 Retry-After: 0을 주더라도 최소 1초는 쉬어 재시도 폭주(503 연쇄)를 막는다
                let delay = retryAfter.map { max(1, $0) } ?? baseBackoff * pow(2, Double(attempt))
                Log.network.info("\(provider, privacy: .public) HTTP \(status) → \(delay)s 후 재시도")
                await limiter.backoff(delay)
            } catch let error as URLError {
                if [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
                    throw HTTPError.offline
                }
                guard error.code == .timedOut, attempt < maxAttempts - 1 else { throw error }
                await limiter.backoff(baseBackoff * pow(2, Double(attempt)))
            }
        }
        throw HTTPError.retriesExhausted(lastStatus)
    }
}
