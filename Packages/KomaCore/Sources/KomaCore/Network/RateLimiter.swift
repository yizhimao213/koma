import Foundation

/// Token-bucket rate limiter. Capacity equals the rate; tokens refill continuously.
public actor RateLimiter {
    private let rate: Double
    private let capacity: Double
    private let now: @Sendable () -> Double
    private let sleep: @Sendable (Double) async -> Void
    private var tokens: Double
    private var lastRefill: Double

    public init(
        ratePerSecond: Int,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
        sleep: @escaping @Sendable (Double) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        let rate = Double(max(1, ratePerSecond))
        self.rate = rate
        self.capacity = rate
        self.now = now
        self.sleep = sleep
        self.tokens = rate
        self.lastRefill = now()
    }

    private func refill() {
        let current = now()
        let elapsed = max(0, current - lastRefill)
        lastRefill = current
        tokens = min(capacity, tokens + elapsed * rate)
    }

    /// Waits until a token is available, then consumes it.
    public func acquire() async {
        refill()
        while tokens < 1 - 1e-9 {
            let wait = (1 - tokens) / rate
            await sleep(wait)
            refill()
        }
        tokens = max(0, tokens - 1)
    }
}
