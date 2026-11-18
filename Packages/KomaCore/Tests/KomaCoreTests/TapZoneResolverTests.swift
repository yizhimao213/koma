import CoreGraphics
import XCTest
@testable import KomaCore

final class TapZoneResolverTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)
    private let resolver = TapZoneResolver()

    func testTapLTR() {
        XCTAssertEqual(resolver.action(for: CGPoint(x: 40, y: 400), in: size, mode: .leftToRight), .previous)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 360, y: 400), in: size, mode: .leftToRight), .next)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 200, y: 400), in: size, mode: .leftToRight), .toggleMenu)
    }

    func testTapRTL() {
        XCTAssertEqual(resolver.action(for: CGPoint(x: 40, y: 400), in: size, mode: .rightToLeft), .next)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 360, y: 400), in: size, mode: .rightToLeft), .previous)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 200, y: 400), in: size, mode: .rightToLeft), .toggleMenu)
    }

    func testTapWebtoon() {
        XCTAssertEqual(resolver.action(for: CGPoint(x: 200, y: 720), in: size, mode: .webtoon), .next)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 200, y: 80), in: size, mode: .webtoon), .previous)
        XCTAssertEqual(resolver.action(for: CGPoint(x: 200, y: 400), in: size, mode: .vertical), .toggleMenu)
    }
}
