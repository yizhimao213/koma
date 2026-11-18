import XCTest
@testable import KomaCore

final class LibraryRepositoryTests: XCTestCase {
    private func makeManga(_ id: String, title: String) -> (MangaDetails, [Chapter]) {
        let ref = MangaRef(sourceId: "local", id: id, title: title)
        let chapters = (0..<3).map {
            Chapter(id: "\(id)-c\($0)", mangaId: id, sourceId: "local", title: "Ch \($0)", number: Double($0), index: $0)
        }
        return (MangaDetails(ref: ref), chapters)
    }

    func testUpsertAndListInLibrary() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        let b = makeManga("b", title: "Beta")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.setInLibrary(a.0.ref, true)
        let items = try repo.items(categoryId: nil, sort: .title)
        XCTAssertEqual(items.map(\.ref.id), ["a"])
        XCTAssertEqual(items.first?.id, "local/a")
    }

    func testUnreadCount() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.setInLibrary(a.0.ref, true)
        try repo.markRead([a.1[0]], true)
        XCTAssertEqual(try repo.items(categoryId: nil, sort: .title).first?.unreadCount, 2)
    }

    func testSortLastRead() throws {
        let db = try AppDatabase.inMemory()
        let repo = LibraryRepository(db)
        let history = HistoryRepository(db)
        let a = makeManga("a", title: "Alpha")
        let b = makeManga("b", title: "Beta")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.setInLibrary(a.0.ref, true)
        Thread.sleep(forTimeInterval: 0.01)
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.setInLibrary(b.0.ref, true)
        try history.save(a.0.ref, progress: ReadingProgress(chapterId: "a-c0", pageIndex: 1, pageCount: 10))
        XCTAssertEqual(try repo.items(categoryId: nil, sort: .lastRead).map(\.ref.id), ["a", "b"])
    }

    func testCategoryFilter() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.setInLibrary(a.0.ref, true)
        let categories = try repo.categories()
        let following = try XCTUnwrap(categories.first { $0.name == "在追" }?.id)
        let finished = try XCTUnwrap(categories.first { $0.name == "已完结" }?.id)
        try repo.assign(a.0.ref, to: [following])
        XCTAssertEqual(try repo.items(categoryId: following, sort: .title).map(\.ref.id), ["a"])
        XCTAssertTrue(try repo.items(categoryId: finished, sort: .title).isEmpty)
    }

    func testSeededCategories() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        XCTAssertEqual(try repo.categories().map(\.name), ["在追", "已完结"])
    }

    func testUpsertKeepsReadState() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.markRead([a.1[0]], true)
        try repo.upsert(details: a.0, chapters: a.1)
        XCTAssertTrue(try repo.isRead(a.1[0]))
        XCTAssertFalse(try repo.isRead(a.1[1]))
    }

    func testReadChapterIds() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        let b = makeManga("b", title: "Beta")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.markRead([a.1[0], a.1[2], b.1[1]], true)
        XCTAssertEqual(try repo.readChapterIds(for: a.0.ref), ["a-c0", "a-c2"])
        XCTAssertEqual(try repo.readChapterIds(for: b.0.ref), ["b-c1"])
    }

    func testIsInLibrary() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        XCTAssertFalse(try repo.isInLibrary(a.0.ref))
        try repo.upsert(details: a.0, chapters: a.1)
        XCTAssertFalse(try repo.isInLibrary(a.0.ref))
        try repo.setInLibrary(a.0.ref, true)
        XCTAssertTrue(try repo.isInLibrary(a.0.ref))
        try repo.setInLibrary(a.0.ref, false)
        XCTAssertFalse(try repo.isInLibrary(a.0.ref))
    }
}
