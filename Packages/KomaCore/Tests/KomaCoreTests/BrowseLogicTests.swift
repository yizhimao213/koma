import XCTest
@testable import KomaCore

final class BrowseLogicTests: XCTestCase {
    private func refs(_ ids: ClosedRange<Int>, source: String = "mangadex") -> [MangaRef] {
        ids.map { MangaRef(sourceId: source, id: "\($0)", title: "T\($0)") }
    }

    func testCacheKeysIncludeAdultState() {
        XCTAssertEqual(BrowseCacheKey.list("popular", adult: true), "popular.adult1")
        XCTAssertEqual(BrowseCacheKey.list("popular", adult: false), "popular.adult0")
        XCTAssertNotEqual(BrowseCacheKey.list("latest", adult: true), BrowseCacheKey.list("latest", adult: false))
        XCTAssertEqual(BrowseCacheKey.adult, "adult")
    }

    func testBeginNextPageGuardsConcurrentLoads() {
        var state = PaginationState()
        XCTAssertEqual(state.beginNextPage(), 1)
        XCTAssertNil(state.beginNextPage())
        state.finish(page: 1, with: MangaPage(items: refs(1...30), hasNextPage: true))
        XCTAssertEqual(state.beginNextPage(), 2)
    }

    func testStopsWhenNoNextPage() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: refs(1...10), hasNextPage: false))
        XCTAssertFalse(state.hasNextPage)
        XCTAssertNil(state.beginNextPage())
        XCTAssertFalse(state.shouldLoadMore(appearingIndex: 9))
    }

    func testEmptyPageStopsPagination() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: [], hasNextPage: true))
        XCTAssertFalse(state.hasNextPage)
    }

    func testShouldLoadMoreOnlyForLastSixItems() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: refs(1...30), hasNextPage: true))
        XCTAssertFalse(state.shouldLoadMore(appearingIndex: 23))
        XCTAssertTrue(state.shouldLoadMore(appearingIndex: 24))
        XCTAssertTrue(state.shouldLoadMore(appearingIndex: 29))
        _ = state.beginNextPage()
        XCTAssertFalse(state.shouldLoadMore(appearingIndex: 29))
    }

    func testFinishAppendsAndDeduplicates() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: refs(1...30), hasNextPage: true))
        _ = state.beginNextPage()
        state.finish(page: 2, with: MangaPage(items: refs(29...58), hasNextPage: true))
        XCTAssertEqual(state.items.count, 58)
        XCTAssertEqual(state.items.map(\.id), (1...58).map { "\($0)" })
        XCTAssertEqual(state.loadedPage, 2)
    }

    func testFailAllowsRetryOfSamePage() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: refs(1...30), hasNextPage: true))
        XCTAssertEqual(state.beginNextPage(), 2)
        state.fail()
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.beginNextPage(), 2)
    }

    func testRefreshKeepsItemsUntilFirstPageArrives() {
        var state = PaginationState()
        _ = state.beginNextPage()
        state.finish(page: 1, with: MangaPage(items: refs(1...30), hasNextPage: true))
        _ = state.beginNextPage()
        state.finish(page: 2, with: MangaPage(items: refs(31...60), hasNextPage: true))
        XCTAssertEqual(state.beginRefresh(), 1)
        XCTAssertEqual(state.items.count, 60)
        XCTAssertTrue(state.isLoading)
        state.finish(page: 1, with: MangaPage(items: refs(5...6), hasNextPage: false))
        XCTAssertEqual(state.items.map(\.id), ["5", "6"])
        XCTAssertEqual(state.loadedPage, 1)
    }

    func testSeedShowsCacheButStillLoadsFirstPage() {
        var state = PaginationState()
        state.seed(with: MangaPage(items: refs(1...3), hasNextPage: true))
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.beginNextPage(), 1)
        state.finish(page: 1, with: MangaPage(items: refs(10...12), hasNextPage: true))
        XCTAssertEqual(state.items.map(\.id), ["10", "11", "12"])
        state.seed(with: MangaPage(items: refs(1...3), hasNextPage: true))
        XCTAssertEqual(state.items.map(\.id), ["10", "11", "12"])
    }

    func testCoverToneClampsBrightnessAndSaturation() {
        let tone = CoverTone.deepened(hue: 0.5, saturation: 0.9, brightness: 0.8)
        XCTAssertEqual(tone.hue, 0.5, accuracy: 0.0001)
        XCTAssertEqual(tone.saturation, 0.6, accuracy: 0.0001)
        XCTAssertEqual(tone.brightness, 0.25, accuracy: 0.0001)
    }

    func testCoverToneKeepsDarkColorsAndSanitizesInput() {
        let dark = CoverTone.deepened(hue: 0.1, saturation: 0.3, brightness: 0.1)
        XCTAssertEqual(dark.saturation, 0.3, accuracy: 0.0001)
        XCTAssertEqual(dark.brightness, 0.1, accuracy: 0.0001)
        let bad = CoverTone.deepened(hue: .nan, saturation: -1, brightness: .infinity)
        XCTAssertEqual(bad.hue, 0)
        XCTAssertEqual(bad.saturation, 0)
        XCTAssertEqual(bad.brightness, 0)
    }
}
