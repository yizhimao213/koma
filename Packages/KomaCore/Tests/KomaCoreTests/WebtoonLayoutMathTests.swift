import CoreGraphics
import XCTest
@testable import KomaCore

final class WebtoonLayoutMathTests: XCTestCase {
    typealias Change = WebtoonLayoutMath.HeightChange

    func testPlaceholderAspect() {
        XCTAssertEqual(WebtoonLayoutMath.placeholderAspect, 1.5)
    }

    func testChangesBelowViewportDoNotMoveOffset() {
        let changes = [Change(minY: 1000, oldHeight: 600, newHeight: 900)]
        XCTAssertEqual(WebtoonLayoutMath.contentOffsetAdjustment(for: changes, visibleTop: 500), 0)
    }

    func testChangeStartingAtViewportTopDoesNotMoveOffset() {
        let changes = [Change(minY: 500, oldHeight: 600, newHeight: 900)]
        XCTAssertEqual(WebtoonLayoutMath.contentOffsetAdjustment(for: changes, visibleTop: 500), 0)
    }

    func testChangesAboveViewportAreSummed() {
        let changes = [
            Change(minY: 0, oldHeight: 600, newHeight: 900),     // +300, above
            Change(minY: 600, oldHeight: 600, newHeight: 400),   // -200, straddles the top
            Change(minY: 2000, oldHeight: 600, newHeight: 1200)  // below, ignored
        ]
        XCTAssertEqual(WebtoonLayoutMath.contentOffsetAdjustment(for: changes, visibleTop: 1000), 100)
    }

    func testItemHeight() {
        XCTAssertEqual(WebtoonLayoutMath.height(forWidth: 400, aspect: nil), 600)
        XCTAssertEqual(WebtoonLayoutMath.height(forWidth: 400, aspect: 2.5), 1000)
        XCTAssertEqual(WebtoonLayoutMath.height(forWidth: 400, aspect: 0), 600)
    }

    // MARK: - Zoom

    private let size = CGSize(width: 400, height: 800)

    func testZoomIdentityKeepsAnchor() {
        let state = WebtoonLayoutMath.zoom(
            scale: 1, anchorContent: CGPoint(x: 100, y: 1300), at: CGPoint(x: 100, y: 300),
            viewSize: size, contentHeight: 10_000)
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.translationX, 0)
        XCTAssertEqual(state.verticalInset, 0)
        XCTAssertEqual(state.contentOffsetY, 1000)
    }

    func testZoomKeepsAnchorUnderFinger() {
        let anchor = CGPoint(x: 300, y: 1500)
        let finger = CGPoint(x: 300, y: 500)
        let state = WebtoonLayoutMath.zoom(
            scale: 2, anchorContent: anchor, at: finger, viewSize: size, contentHeight: 10_000)
        XCTAssertEqual(state.scale, 2)
        XCTAssertEqual(state.verticalInset, 200)
        // Map the anchor back to the screen: c + s * (v - c) + t.
        let vx = anchor.x
        let vy = anchor.y - state.contentOffsetY
        XCTAssertEqual(200 + 2 * (vx - 200) + state.translationX, finger.x, accuracy: 0.001)
        XCTAssertEqual(400 + 2 * (vy - 400), finger.y, accuracy: 0.001)
        // And the inverse mapping returns the anchor.
        let back = WebtoonLayoutMath.contentPoint(at: finger, state: state, viewSize: size)
        XCTAssertEqual(back.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(back.y, anchor.y, accuracy: 0.001)
    }

    func testZoomClampsScaleTranslationAndOffset() {
        let state = WebtoonLayoutMath.zoom(
            scale: 10, anchorContent: CGPoint(x: 0, y: 0), at: CGPoint(x: 400, y: 800),
            viewSize: size, contentHeight: 10_000)
        XCTAssertEqual(state.scale, 3)
        XCTAssertEqual(state.translationX, 400)          // (3 - 1) * 400 / 2
        XCTAssertEqual(state.verticalInset, 800.0 / 3, accuracy: 0.001)
        XCTAssertEqual(state.contentOffsetY, -800.0 / 3, accuracy: 0.001)
    }

    func testZoomBelowOneClampsToOne() {
        let state = WebtoonLayoutMath.zoom(
            scale: 0.5, anchorContent: CGPoint(x: 200, y: 99_999), at: CGPoint(x: 200, y: 400),
            viewSize: size, contentHeight: 10_000)
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.contentOffsetY, 9_200)  // clamped to contentHeight - height
    }
}
