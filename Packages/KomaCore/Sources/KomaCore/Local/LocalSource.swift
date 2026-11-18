import Foundation

public struct LocalSource: MangaSource {
    public let id = "local"
    public let name = "本地漫画"
    public let language = "multi"
    public var icon: URL? { nil }

    private let libraryRoot: URL

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
    }

    public func popular(page: Int) async throws -> MangaPage {
        MangaPage(items: listAll(), hasNextPage: false)
    }

    public func latest(page: Int) async throws -> MangaPage {
        MangaPage(items: listAll(), hasNextPage: false)
    }

    public func search(query: String, filters: [String: String], page: Int) async throws -> MangaPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = listAll()
        let items = trimmed.isEmpty ? all : all.filter { $0.title.range(of: trimmed, options: .caseInsensitive) != nil }
        return MangaPage(items: items, hasNextPage: false)
    }

    public func details(for manga: MangaRef) async throws -> MangaDetails {
        let (ref, _) = try load(manga.id)
        return MangaDetails(ref: ref, author: nil, description: nil, tags: [], status: .unknown)
    }

    public func chapters(for manga: MangaRef) async throws -> [Chapter] {
        let (_, meta) = try load(manga.id)
        return meta.chapters.enumerated().map { offset, chapter in
            Chapter(id: chapter.id, mangaId: manga.id, sourceId: id, title: chapter.title, number: nil, index: offset)
        }
    }

    public func pages(for chapter: Chapter) async throws -> [PageRef] {
        let dir = libraryRoot
            .appendingPathComponent(chapter.mangaId, isDirectory: true)
            .appendingPathComponent(chapter.id, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            throw SourceError.notFound
        }
        let files = names
            .filter { localImageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        return files.enumerated().map { offset, name in
            PageRef(index: offset, url: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Helpers

    private func load(_ mangaId: String) throws -> (MangaRef, LocalMangaMeta) {
        let dir = libraryRoot.appendingPathComponent(mangaId, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manga.json")),
              let meta = try? LocalMangaMeta.makeDecoder().decode(LocalMangaMeta.self, from: data)
        else {
            throw SourceError.notFound
        }
        var cover: URL?
        if let first = meta.chapters.first {
            cover = LocalImporter.firstPage(in: dir.appendingPathComponent(first.id, isDirectory: true))
        }
        return (MangaRef(sourceId: id, id: mangaId, title: meta.title, coverURL: cover), meta)
    }

    /// Newest import first; ties broken by title.
    private func listAll() -> [MangaRef] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: libraryRoot.path)) ?? []
        var entries: [(MangaRef, Date)] = []
        for name in names {
            guard !name.hasPrefix("."), let (ref, meta) = try? load(name) else { continue }
            entries.append((ref, meta.importedAt ?? .distantPast))
        }
        entries.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.title.naturalCompare(rhs.0.title) == .orderedAscending
        }
        return entries.map { $0.0 }
    }
}
