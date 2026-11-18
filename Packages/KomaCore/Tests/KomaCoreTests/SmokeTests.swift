import XCTest
@testable import KomaCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(KomaCore.version, "0.1.0")
    }
}
