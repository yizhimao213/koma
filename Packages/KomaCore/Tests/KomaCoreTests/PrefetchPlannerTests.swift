import XCTest
@testable import KomaCore

final class PrefetchPlannerTests: XCTestCase {
    func testPrefetchMiddle() {
        XCTAssertEqual(PrefetchPlanner().indices(around: 10, count: 100), [11, 9, 12, 8, 13, 14, 15])
    }

    func testPrefetchClamped() {
        XCTAssertEqual(PrefetchPlanner().indices(around: 0, count: 3), [1, 2])
    }
}
