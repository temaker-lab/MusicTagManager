import Foundation

/// 요청 간 최소 간격을 지키는 전역 리미터. 외부 API별로 하나씩 둔다.
public actor RateLimiter {
    public let interval: TimeInterval
    private var nextSlot = Date.distantPast

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// 다음 요청 시각까지 기다린다. 슬롯을 먼저 예약하므로 동시에 불려도 간격이 유지된다.
    public func acquire() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    /// 429·503 등을 받으면 이후 요청 전체를 늦춘다.
    public func backoff(_ seconds: TimeInterval) {
        nextSlot = max(nextSlot, Date().addingTimeInterval(seconds))
    }
}
