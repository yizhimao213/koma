import XCTest
@testable import KomaCore

@MainActor
final class ReaderSessionTests: XCTestCase {
    private func chapter(_ id: String, index: Int) -> Chapter {
        Chapter(id: id, mangaId: "m", sourceId: "local", title: id, number: Double(index + 1), index: index)
    }

    private func makePages(_ count: Int) -> [PageRef] {
        (0..<count).map { PageRef(index: $0, url: URL(string: "https://example.com/\($0).jpg")!) }
    }

    private final class CallLog {
        var calls: [String] = []
    }

    func testSessionStartsAtSavedPage() async throws {
        let c1 = chapter("c1", index: 0)
        let pages = makePages(10)
        let session = ReaderSession(chapters: [c1], startChapterId: "c1", startPage: 7) { _ in pages }
        try await session.start()
        XCTAssertEqual(session.currentIndex, 7)
        let progress = try XCTUnwrap(session.currentProgress)
        XCTAssertEqual(progress.chapterId, "c1")
        XCTAssertEqual(progress.pageIndex, 7)
        XCTAssertEqual(progress.pageCount, 10)
        XCTAssertEqual(session.currentChapter, c1)
    }

    func testSessionAppendsNextChapter() async throws {
        let c1 = chapter("c1", index: 0)
        let c2 = chapter("c2", index: 1)
        let log = CallLog()
        let p1 = makePages(5)
        let p2 = makePages(4)
        let session = ReaderSession(chapters: [c1, c2], startChapterId: "c1", startPage: 0) { chapter in
            log.calls.append(chapter.id)
            return chapter.id == "c1" ? p1 : p2
        }
        try await session.start()
        await session.didShow(index: 3)
        await session.didShow(index: 3)
        await session.didShow(index: 4)

        var expected: [ReaderItem] = p1.map { ReaderItem.page(chapterId: "c1", $0) }
        expected.append(.transition(from: c1, to: c2))
        expected.append(contentsOf: p2.map { ReaderItem.page(chapterId: "c2", $0) })
        expected.append(.transition(from: c2, to: nil))
        XCTAssertEqual(session.items, expected)
        XCTAssertEqual(log.calls, ["c1", "c2"])
    }

    func testTransitionHasNoProgress() async throws {
        let c1 = chapter("c1", index: 0)
        let pages = makePages(3)
        let session = ReaderSession(chapters: [c1], startChapterId: "c1", startPage: 0) { _ in pages }
        try await session.start()
        await session.didShow(index: 3)
        XCTAssertEqual(session.currentIndex, 3)
        XCTAssertNil(session.currentProgress)
    }

    func testTransitionMapsToFinishedProgress() async throws {
        let c1 = chapter("c1", index: 0)
        let pages = makePages(3)
        let session = ReaderSession(chapters: [c1], startChapterId: "c1", startPage: 0) { _ in pages }
        try await session.start()
        await session.didShow(index: 3)
        let progress = try XCTUnwrap(session.progressForSaving)
        XCTAssertEqual(progress.chapterId, "c1")
        XCTAssertEqual(progress.pageIndex, 2)
        XCTAssertEqual(progress.pageCount, 3)
        XCTAssertNil(session.currentProgress)
    }

    func testProgressForSavingOnPageMatchesCurrentProgress() async throws {
        let c1 = chapter("c1", index: 0)
        let pages = makePages(5)
        let session = ReaderSession(chapters: [c1], startChapterId: "c1", startPage: 1) { _ in pages }
        try await session.start()
        let saving = try XCTUnwrap(session.progressForSaving(at: 1))
        XCTAssertEqual(saving.chapterId, "c1")
        XCTAssertEqual(saving.pageIndex, 1)
        XCTAssertEqual(saving.pageCount, 5)
        XCTAssertNil(session.progressForSaving(at: 99))
    }

    func testJumpResetsItems() async throws {
        let c1 = chapter("c1", index: 0)
        let c2 = chapter("c2", index: 1)
        let pages = makePages(4)
        let session = ReaderSession(chapters: [c1, c2], startChapterId: "c1", startPage: 2) { _ in pages }
        try await session.start()
        try await session.jump(toChapter: "c2")
        XCTAssertEqual(session.items.count, 5)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.currentProgress?.chapterId, "c2")
    }
}
