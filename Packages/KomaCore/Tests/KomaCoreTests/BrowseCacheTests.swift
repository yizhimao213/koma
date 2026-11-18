import XCTest
@testable import KomaCore

final class BrowseCacheTests: XCTestCase {
    private func makeDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("browse-cache-\(UUID().uuidString)", isDirectory: true)
    }

    func testBrowseCacheRoundTrip() {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BrowseCache(directory: dir)
        let page = MangaPage(items: [
            MangaRef(sourceId: "mangadex", id: "1", title: "One", coverURL: URL(string: "https://example.com/1.jpg")),
            MangaRef(sourceId: "mangadex", id: "2", title: "Two")
        ], hasNextPage: true)
        cache.store(page, sourceId: "mangadex", kind: "popular")
        let loaded = cache.load(sourceId: "mangadex", kind: "popular")
        XCTAssertEqual(loaded?.items, page.items)
        XCTAssertEqual(loaded?.hasNextPage, true)
    }

    func testBrowseCacheMissReturnsNil() {
        let cache = BrowseCache(directory: makeDir())
        XCTAssertNil(cache.load(sourceId: "mangadex", kind: "latest"))
    }

    func testBrowseCacheCorruptedFileReturnsNil() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BrowseCache(directory: dir)
        cache.store(MangaPage(items: [], hasNextPage: false), sourceId: "s", kind: "k")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data("not json".utf8).write(to: file)
        XCTAssertNil(cache.load(sourceId: "s", kind: "k"))
    }

    func testBrowseCacheKindsAreIndependent() {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BrowseCache(directory: dir)
        cache.store(MangaPage(items: [MangaRef(sourceId: "s", id: "a", title: "A")], hasNextPage: false), sourceId: "s", kind: "popular")
        XCTAssertNil(cache.load(sourceId: "s", kind: "latest"))
        XCTAssertEqual(cache.load(sourceId: "s", kind: "popular")?.items.map(\.id), ["a"])
    }
}
