import XCTest
@testable import KomaCore

final class NaturalSortTests: XCTestCase {
    func testNaturalSortNumbers() {
        XCTAssertEqual(["10.jpg", "2.jpg", "1.jpg"].naturallySorted(), ["1.jpg", "2.jpg", "10.jpg"])
    }

    func testNaturalSortChapters() {
        XCTAssertEqual(["第10话", "第2话", "第1话"].naturallySorted(), ["第1话", "第2话", "第10话"])
    }

    func testNaturalSortPaths() {
        XCTAssertEqual(
            ["ch2/1.png", "ch10/1.png", "ch1/12.png", "ch1/3.png"].naturallySorted(),
            ["ch1/3.png", "ch1/12.png", "ch2/1.png", "ch10/1.png"]
        )
    }
}
