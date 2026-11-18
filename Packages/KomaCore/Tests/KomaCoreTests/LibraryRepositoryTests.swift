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

    func testSameChapterIdsAcrossMangaAreIndependent() throws {
        let db = try AppDatabase.inMemory()
        let repo = LibraryRepository(db)
        let history = HistoryRepository(db)
        func manga(_ id: String) -> (MangaDetails, [Chapter]) {
            let ref = MangaRef(sourceId: "local", id: id, title: id)
            return (MangaDetails(ref: ref), [
                Chapter(id: "c0001", mangaId: id, sourceId: "local", title: "One", number: nil, index: 0),
                Chapter(id: "c0002", mangaId: id, sourceId: "local", title: "Two", number: nil, index: 1)
            ])
        }
        let a = manga("A")
        let b = manga("B")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.setInLibrary(a.0.ref, true)
        try repo.markRead([a.1[0]], true)
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.setInLibrary(b.0.ref, true)

        XCTAssertTrue(try repo.isRead(a.1[0]))
        XCTAssertFalse(try repo.isRead(b.1[0]))
        XCTAssertEqual(try repo.chapters(for: a.0.ref).map(\.id), ["c0001", "c0002"])
        XCTAssertEqual(try repo.chapters(for: b.0.ref).map(\.id), ["c0001", "c0002"])
        let unread = Dictionary(uniqueKeysWithValues:
            try repo.items(categoryId: nil, sort: .title).map { ($0.ref.id, $0.unreadCount) })
        XCTAssertEqual(unread, ["A": 1, "B": 2])

        // Saving B's last page must not mark A's chapter read.
        try history.save(b.0.ref, progress: ReadingProgress(chapterId: "c0002", pageIndex: 4, pageCount: 5))
        XCTAssertTrue(try repo.isRead(b.1[1]))
        XCTAssertFalse(try repo.isRead(a.1[1]))
        XCTAssertEqual(try repo.readChapterIds(for: a.0.ref), ["c0001"])
    }

    func testLocalCoverStoredRelativeAndResolved() throws {
        let db = try AppDatabase.inMemory()
        let rootA = URL(fileURLWithPath: "/containerA/Documents/Library", isDirectory: true)
        let rootB = URL(fileURLWithPath: "/containerB/Documents/Library", isDirectory: true)
        let writerRepo = LibraryRepository(db, coverResolver: CoverURLResolver(libraryRoot: rootA))
        let cover = rootA.appendingPathComponent("m1/c0001/0001.jpg")
        let ref = MangaRef(sourceId: "local", id: "m1", title: "One", coverURL: cover)
        try writerRepo.upsert(details: MangaDetails(ref: ref), chapters: [])
        try writerRepo.setInLibrary(ref, true)

        let stored: String? = try db.writer.read {
            try String.fetchOne($0, sql: "SELECT coverURL FROM manga WHERE id = 'm1'")
        }
        XCTAssertEqual(stored, "local-library:/m1/c0001/0001.jpg")

        let readerRepo = LibraryRepository(db, coverResolver: CoverURLResolver(libraryRoot: rootB))
        let item = try XCTUnwrap(readerRepo.items(categoryId: nil, sort: .title).first)
        XCTAssertEqual(item.ref.coverURL?.path, "/containerB/Documents/Library/m1/c0001/0001.jpg")

        let history = HistoryRepository(db, coverResolver: CoverURLResolver(libraryRoot: rootB))
        try history.save(ref, progress: ReadingProgress(chapterId: "c0001", pageIndex: 0, pageCount: 3))
        XCTAssertEqual(try history.recent(limit: 5).first?.0.coverURL?.path,
                       "/containerB/Documents/Library/m1/c0001/0001.jpg")
    }

    func testUpsertPruneMissing() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.setInLibrary(a.0.ref, true)
        let b = makeManga("b", title: "Beta")
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.upsert(details: a.0, chapters: Array(a.1.prefix(2)), pruneMissing: true)
        XCTAssertEqual(try repo.chapters(for: a.0.ref).count, 2)
        XCTAssertEqual(try repo.items(categoryId: nil, sort: .title).first?.unreadCount, 2)
        XCTAssertEqual(try repo.chapters(for: b.0.ref).count, 3)
    }

    func testPruneKeepsHistoryChapter() throws {
        let db = try AppDatabase.inMemory()
        let repo = LibraryRepository(db)
        let history = HistoryRepository(db)
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try history.save(a.0.ref, progress: ReadingProgress(chapterId: "a-c2", pageIndex: 1, pageCount: 10))
        try repo.upsert(details: a.0, chapters: Array(a.1.prefix(2)), pruneMissing: true)
        XCTAssertTrue(try repo.chapters(for: a.0.ref).contains { $0.id == "a-c2" })
        let recent = try history.recent(limit: 5)
        XCTAssertEqual(recent.first?.1.chapterId, "a-c2")
    }

    func testUpsertWithoutPruneKeeps() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.upsert(details: a.0, chapters: Array(a.1.prefix(2)))
        XCTAssertEqual(try repo.chapters(for: a.0.ref).count, 3)
    }

    func testLibraryRefsOnlyInLibrary() throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let a = makeManga("a", title: "Alpha")
        let b = makeManga("b", title: "Beta")
        try repo.upsert(details: a.0, chapters: a.1)
        try repo.upsert(details: b.0, chapters: b.1)
        try repo.setInLibrary(a.0.ref, true)
        XCTAssertEqual(try repo.libraryRefs().map(\.id), ["a"])
    }

    func testRemoteCoverPassesThrough() throws {
        let resolver = CoverURLResolver(libraryRoot: URL(fileURLWithPath: "/x/Library"))
        let url = URL(string: "https://example.com/c.jpg")
        XCTAssertEqual(resolver.storedString(for: url), "https://example.com/c.jpg")
        XCTAssertEqual(resolver.resolve(stored: "https://example.com/c.jpg"), url)
    }
}
