import XCTest
@testable import KomaCore

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    func record(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return ids }
}

private struct UpdaterStubSource: MangaSource {
    let id: String
    let name = "Stub"
    let language = "en"
    let icon: URL? = nil
    let chapterIds: [String]
    let shouldFail: Bool
    let recorder: CallRecorder

    func popular(page: Int) async throws -> MangaPage { throw SourceError.unsupported }
    func latest(page: Int) async throws -> MangaPage { throw SourceError.unsupported }
    func search(query: String, filters: [String: String], page: Int) async throws -> MangaPage {
        throw SourceError.unsupported
    }
    func details(for manga: MangaRef) async throws -> MangaDetails {
        recorder.record(manga.id)
        if shouldFail { throw SourceError.network("boom") }
        return MangaDetails(ref: manga)
    }
    func chapters(for manga: MangaRef) async throws -> [Chapter] {
        chapterIds.enumerated().map {
            Chapter(id: $0.element, mangaId: manga.id, sourceId: manga.sourceId, title: $0.element, number: nil, index: $0.offset)
        }
    }
    func pages(for chapter: Chapter) async throws -> [PageRef] { throw SourceError.unsupported }
}

final class LibraryUpdaterTests: XCTestCase {
    private func seed(_ repo: LibraryRepository, sourceId: String, id: String, chapterIds: [String]) throws -> MangaRef {
        let ref = MangaRef(sourceId: sourceId, id: id, title: id)
        let chapters = chapterIds.enumerated().map {
            Chapter(id: $0.element, mangaId: id, sourceId: sourceId, title: $0.element, number: nil, index: $0.offset)
        }
        try repo.upsert(details: MangaDetails(ref: ref), chapters: chapters)
        try repo.setInLibrary(ref, true)
        return ref
    }

    func testUpdaterCountsNewChapters() async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let ref = try seed(repo, sourceId: "stub", id: "m1", chapterIds: ["c1", "c2"])
        let source = UpdaterStubSource(id: "stub", chapterIds: ["c1", "c2", "c3", "c4"], shouldFail: false, recorder: CallRecorder())
        let updater = LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source]))
        let result = await updater.refreshAll()
        XCTAssertEqual(result, LibraryUpdateResult(updatedMangaCount: 1, newChapterCount: 2, failedCount: 0))
        XCTAssertEqual(try repo.chapters(for: ref).map(\.id), ["c1", "c2", "c3", "c4"])
    }

    func testUpdaterPrunesRemovedChapters() async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let ref = try seed(repo, sourceId: "stub", id: "m1", chapterIds: ["c1", "c2", "c3"])
        let source = UpdaterStubSource(id: "stub", chapterIds: ["c1", "c2"], shouldFail: false, recorder: CallRecorder())
        let result = await LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source])).refreshAll()
        XCTAssertEqual(result, LibraryUpdateResult(updatedMangaCount: 0, newChapterCount: 0, failedCount: 0))
        XCTAssertEqual(try repo.chapters(for: ref).map(\.id), ["c1", "c2"])
    }

    func testUpdaterEmptyChapterListDoesNotWipe() async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let ref = try seed(repo, sourceId: "stub", id: "m1", chapterIds: ["c1", "c2", "c3"])
        let chapters = try repo.chapters(for: ref)
        try repo.markRead([chapters[0]], true)
        let source = UpdaterStubSource(id: "stub", chapterIds: [], shouldFail: false, recorder: CallRecorder())
        let result = await LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source])).refreshAll()
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try repo.chapters(for: ref).count, 3)
        XCTAssertTrue(try repo.isRead(chapters[0]))
    }

    func testUpdaterSkipsLocal()async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        let ref = try seed(repo, sourceId: "local", id: "l1", chapterIds: ["c1"])
        let recorder = CallRecorder()
        let source = UpdaterStubSource(id: "local", chapterIds: [], shouldFail: false, recorder: recorder)
        let result = await LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source])).refreshAll()
        XCTAssertEqual(result, LibraryUpdateResult(updatedMangaCount: 0, newChapterCount: 0, failedCount: 0))
        XCTAssertTrue(recorder.all.isEmpty)
        XCTAssertEqual(try repo.chapters(for: ref).map(\.id), ["c1"])
    }

    func testUpdaterCountsFailures() async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        _ = try seed(repo, sourceId: "stub", id: "m1", chapterIds: ["c1"])
        let source = UpdaterStubSource(id: "stub", chapterIds: [], shouldFail: true, recorder: CallRecorder())
        let result = await LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source])).refreshAll()
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.updatedMangaCount, 0)
    }

    func testUpdaterHandlesManyMangaWithBoundedConcurrency() async throws {
        let repo = LibraryRepository(try AppDatabase.inMemory())
        for i in 0..<7 { _ = try seed(repo, sourceId: "stub", id: "m\(i)", chapterIds: ["c1"]) }
        let source = UpdaterStubSource(id: "stub", chapterIds: ["c1", "c2"], shouldFail: false, recorder: CallRecorder())
        let result = await LibraryUpdater(library: repo, sources: SourceRegistry(sources: [source]), maxConcurrent: 2).refreshAll()
        XCTAssertEqual(result, LibraryUpdateResult(updatedMangaCount: 7, newChapterCount: 7, failedCount: 0))
    }
}
