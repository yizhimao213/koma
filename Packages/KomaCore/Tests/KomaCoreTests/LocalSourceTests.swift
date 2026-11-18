import XCTest
@testable import KomaCore

final class LocalSourceTests: XCTestCase {
    var work: URL!
    var library: URL!

    override func setUpWithError() throws {
        work = try LocalTestSupport.makeTempDir()
        library = work.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func importTwo() throws -> (MangaRef, MangaRef) {
        let importer = LocalImporter(libraryRoot: library)
        let a = work.appendingPathComponent("MyManga.cbz")
        try LocalTestSupport.makeZip(at: a, entries: [
            ("2.jpg", LocalTestSupport.fakeImage("2")),
            ("1.jpg", LocalTestSupport.fakeImage("1")),
            ("3.jpg", LocalTestSupport.fakeImage("3"))
        ])
        let b = work.appendingPathComponent("Other.cbz")
        try LocalTestSupport.makeZip(at: b, entries: [("1.png", LocalTestSupport.fakeImage("x"))])
        return (try importer.importItem(at: a), try importer.importItem(at: b))
    }

    func testLocalSourceListsAndPages() async throws {
        let (mine, _) = try importTwo()
        let source = LocalSource(libraryRoot: library)
        XCTAssertEqual(source.id, "local")
        XCTAssertEqual(source.language, "multi")
        let popular = try await source.popular(page: 1)
        XCTAssertEqual(popular.items.count, 2)
        XCTAssertFalse(popular.hasNextPage)
        let latest = try await source.latest(page: 1)
        XCTAssertEqual(latest.items.count, 2)

        let details = try await source.details(for: mine)
        XCTAssertEqual(details.ref.title, "MyManga")
        let chapters = try await source.chapters(for: mine)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].id, "c0001")
        XCTAssertEqual(chapters[0].mangaId, mine.id)
        XCTAssertEqual(chapters[0].sourceId, "local")
        XCTAssertEqual(chapters[0].index, 0)

        let pages = try await source.pages(for: chapters[0])
        XCTAssertEqual(pages.map { $0.index }, [0, 1, 2])
        for page in pages {
            XCTAssertTrue(page.url.isFileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.url.path))
        }
    }

    func testLocalSourceSearch() async throws {
        _ = try importTwo()
        let source = LocalSource(libraryRoot: library)
        let result = try await source.search(query: "my", filters: [:], page: 1)
        XCTAssertEqual(result.items.map { $0.title }, ["MyManga"])
        let none = try await source.search(query: "zzz", filters: [:], page: 1)
        XCTAssertTrue(none.items.isEmpty)
    }
}
