import XCTest
@testable import KomaCore

final class HistoryRepositoryTests: XCTestCase {
    private let ref = MangaRef(sourceId: "local", id: "m1", title: "One")

    private func seed(_ db: AppDatabase) throws {
        let chapters = (0..<3).map {
            Chapter(id: "c\($0)", mangaId: "m1", sourceId: "local", title: "Ch \($0)", number: Double($0), index: $0)
        }
        try LibraryRepository(db).upsert(details: MangaDetails(ref: ref), chapters: chapters)
    }

    func testProgressRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let progress = ReadingProgress(
            chapterId: "c2", pageIndex: 7, pageCount: 20,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        do {
            let db = try AppDatabase.onDisk(at: url)
            try seed(db)
            try HistoryRepository(db).save(ref, progress: progress)
        }
        let reopened = try AppDatabase.onDisk(at: url)
        XCTAssertEqual(try HistoryRepository(reopened).progress(for: ref), progress)
    }

    func testFinishingChapterMarksRead() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        try HistoryRepository(db).save(ref, progress: ReadingProgress(chapterId: "c1", pageIndex: 19, pageCount: 20))
        let library = LibraryRepository(db)
        let chapters = try library.chapters(for: ref)
        XCTAssertEqual(try library.isRead(chapters[1]), true)
        XCTAssertEqual(try library.isRead(chapters[0]), false)
    }

    func testRecentAndDelete() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        let history = HistoryRepository(db)
        try history.save(ref, progress: ReadingProgress(chapterId: "c0", pageIndex: 1, pageCount: 5))
        XCTAssertEqual(try history.recent(limit: 10).map(\.0.id), ["m1"])
        try history.delete(ref)
        XCTAssertNil(try history.progress(for: ref))
        XCTAssertTrue(try history.recent(limit: 10).isEmpty)
    }
}
