import XCTest
@testable import KomaCore

private struct StubSource: MangaSource {
    let id: String
    let name = "Stub"
    let language = "en"
    let icon: URL? = nil

    func popular(page: Int) async throws -> MangaPage { throw SourceError.unsupported }
    func latest(page: Int) async throws -> MangaPage { throw SourceError.unsupported }
    func search(query: String, filters: [String: String], page: Int) async throws -> MangaPage {
        throw SourceError.unsupported
    }
    func details(for manga: MangaRef) async throws -> MangaDetails { throw SourceError.notFound }
    func chapters(for manga: MangaRef) async throws -> [Chapter] { throw SourceError.notFound }
    func pages(for chapter: Chapter) async throws -> [PageRef] { throw SourceError.notFound }
}

final class SourceRegistryTests: XCTestCase {
    func testRegistryLookup() {
        let registry = SourceRegistry(sources: [StubSource(id: "stub")])
        XCTAssertEqual(registry.source(id: "stub")?.id, "stub")
        XCTAssertNil(registry.source(id: "missing"))
        XCTAssertEqual(registry.all.map(\.id), ["stub"])
    }
}
