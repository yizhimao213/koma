import XCTest
@testable import KomaCore

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double = 0
    private var recorded: [Double] = []

    func now() -> Double {
        lock.lock(); defer { lock.unlock() }
        return time
    }

    func sleep(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(seconds)
        time += seconds
    }

    var sleeps: [Double] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

final class RateLimiterTests: XCTestCase {
    func testRateLimiterSpacesBursts() async {
        let clock = FakeClock()
        let limiter = RateLimiter(
            ratePerSecond: 5,
            now: { clock.now() },
            sleep: { clock.sleep($0) }
        )
        for _ in 0..<7 {
            await limiter.acquire()
        }
        let sleeps = clock.sleeps
        XCTAssertEqual(sleeps.count, 2)
        XCTAssertGreaterThanOrEqual(sleeps.reduce(0, +), 0.4 - 1e-9)
    }

    func testBurstWithinCapacityDoesNotSleep() async {
        let clock = FakeClock()
        let limiter = RateLimiter(
            ratePerSecond: 5,
            now: { clock.now() },
            sleep: { clock.sleep($0) }
        )
        for _ in 0..<5 {
            await limiter.acquire()
        }
        XCTAssertTrue(clock.sleeps.isEmpty)
    }
}
