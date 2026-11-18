import Foundation

public enum SourceError: Error, Equatable {
    case notFound
    case unsupported
    case network(String)
    case parse(String)
}

public protocol MangaSource: Sendable {
    var id: String { get }
    var name: String { get }
    var language: String { get }
    var icon: URL? { get }

    func popular(page: Int) async throws -> MangaPage
    func latest(page: Int) async throws -> MangaPage
    func search(query: String, filters: [String: String], page: Int) async throws -> MangaPage
    func details(for manga: MangaRef) async throws -> MangaDetails
    func chapters(for manga: MangaRef) async throws -> [Chapter]
    func pages(for chapter: Chapter) async throws -> [PageRef]
}
