import XCTest
@testable import KomaCore

final class ReaderAppendPolicyTests: XCTestCase {
    func testRightToLeftDefersWhileScrolling() {
        XCTAssertTrue(ReaderAppendPolicy.shouldDeferAppend(mode: .rightToLeft, isDragging: true, isDecelerating: false, isAnimatingScroll: false))
        XCTAssertTrue(ReaderAppendPolicy.shouldDeferAppend(mode: .rightToLeft, isDragging: false, isDecelerating: true, isAnimatingScroll: false))
        XCTAssertTrue(ReaderAppendPolicy.shouldDeferAppend(mode: .rightToLeft, isDragging: false, isDecelerating: false, isAnimatingScroll: true))
    }

    func testRightToLeftAppliesAtRest() {
        XCTAssertFalse(ReaderAppendPolicy.shouldDeferAppend(mode: .rightToLeft, isDragging: false, isDecelerating: false, isAnimatingScroll: false))
    }

    func testOtherModesNeverDefer() {
        for mode in [ReadingMode.leftToRight, .vertical, .webtoon] {
            XCTAssertFalse(ReaderAppendPolicy.shouldDeferAppend(mode: mode, isDragging: true, isDecelerating: true, isAnimatingScroll: true))
        }
    }
}
