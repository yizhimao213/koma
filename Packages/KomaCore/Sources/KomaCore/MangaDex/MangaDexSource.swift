import Foundation

public final class MangaDexSource: MangaSource, @unchecked Sendable {
    public let id = "mangadex"
    public let name = "MangaDex"
    public let language = "multi"
    public var icon: URL? { nil }

    private let client: HTTPClient
    private let settings: @Sendable () -> NetworkSettings

    public init(client: HTTPClient, settings: @escaping @Sendable () -> NetworkSettings) {
        self.client = client
        self.settings = settings
    }

    // MARK: - MangaSource

    public func popular(page: Int) async throws -> MangaPage {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        return try await fetchList(
            builder.mangaList(page: page, order: .followedCount, ratings: builder.browseRatings),
            settings: s
        )
    }

    public func latest(page: Int) async throws -> MangaPage {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        return try await fetchList(
            builder.mangaList(page: page, order: .latestUploadedChapter, ratings: builder.browseRatings),
            settings: s
        )
    }

    public func search(query: String, filters: [String: String], page: Int) async throws -> MangaPage {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        let request = builder.mangaList(
            page: page,
            order: .followedCount,
            ratings: builder.browseRatings,
            title: query,
            status: filters["status"]
        )
        return try await fetchList(request, settings: s)
    }

    public func featured() async throws -> [MangaRef] {
        Array(try await popular(page: 1).items.prefix(8))
    }

    public func adultPicks(page: Int) async throws -> MangaPage {
        let s = settings()
        guard s.showAdult else { throw SourceError.unsupported }
        let builder = MangaDexRequestBuilder(settings: s)
        return try await fetchList(
            builder.mangaList(page: page, order: .followedCount, ratings: MangaDexRequestBuilder.adultRatings),
            settings: s
        )
    }

    public func details(for manga: MangaRef) async throws -> MangaDetails {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        let entity: MDEntity<MDManga> = try await fetch(builder.details(id: manga.id))
        let dto = entity.data
        let ref = makeRef(dto, builder: builder)

        let attrs = dto.attributes
        let description = Self.pick(attrs.description?.values, priority: ["zh", "zh-hk", "en"])
        var tags: [String] = (attrs.tags ?? []).compactMap { tag in
            Self.pick(tag.attributes?.name?.values, priority: ["zh", "en"])
        }
        if attrs.contentRating == "erotica" || attrs.contentRating == "pornographic" {
            tags.append("18+")
        }
        let status: MangaStatus
        switch attrs.status {
        case "ongoing": status = .ongoing
        case "completed": status = .completed
        default: status = .unknown
        }
        let author = dto.relationships?.first(where: { $0.type == "author" })?.attributes?.name
        return MangaDetails(ref: ref, author: author, description: description, tags: tags, status: status)
    }

    public func chapters(for manga: MangaRef) async throws -> [Chapter] {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        var collected: [MDChapter] = []
        var offset = 0
        while true {
            let list: MDList<MDChapter> = try await fetch(builder.feed(id: manga.id, offset: offset))
            collected.append(contentsOf: list.data)
            let limit = list.limit ?? MangaDexRequestBuilder.feedPageSize
            let total = list.total ?? 0
            if list.data.isEmpty || offset + limit >= total { break }
            offset += limit
        }
        return Self.buildChapters(collected, mangaId: manga.id, sourceId: id, languages: s.languages)
    }

    public func pages(for chapter: Chapter) async throws -> [PageRef] {
        let s = settings()
        let builder = MangaDexRequestBuilder(settings: s)
        let home: MDAtHome = try await fetch(builder.atHome(chapterId: chapter.id))
        let segment = s.dataSaver ? "data-saver" : "data"
        let files = s.dataSaver ? home.chapter.dataSaver : home.chapter.data
        let hash = home.chapter.hash
        let uploads = MangaDexRequestBuilder.trimmed(s.uploadsBaseURL)
        var nodeBase = home.baseUrl
        while nodeBase.hasSuffix("/") { nodeBase.removeLast() }
        let primaryHost = s.usesCustomUploads ? uploads : nodeBase

        var result: [PageRef] = []
        for (index, file) in files.enumerated() {
            guard let primary = builder.pageURL(host: primaryHost, segment: segment, hash: hash, file: file) else {
                throw SourceError.parse("Invalid page URL for \(file)")
            }
            let fallback = builder.pageURL(host: uploads, segment: segment, hash: hash, file: file)
            result.append(PageRef(
                index: index,
                url: primary,
                fallbackURL: (fallback == primary) ? nil : fallback
            ))
        }
        return result
    }

    // MARK: - Networking

    private func fetch<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        do {
            let (body, _) = try await client.data(for: request)
            data = body
        } catch let error as HTTPError {
            if error.statusCode == 404 { throw SourceError.notFound }
            throw SourceError.network("HTTP \(error.statusCode)")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.parse(String(describing: error))
        }
    }

    private func fetchList(_ request: URLRequest, settings: NetworkSettings) async throws -> MangaPage {
        let list: MDList<MDManga> = try await fetch(request)
        let builder = MangaDexRequestBuilder(settings: settings)
        let items = list.data.map { makeRef($0, builder: builder) }
        let offset = list.offset ?? 0
        let limit = list.limit ?? MangaDexRequestBuilder.pageSize
        let total = list.total ?? 0
        return MangaPage(items: items, hasNextPage: offset + limit < total)
    }

    // MARK: - Mapping

    private func makeRef(_ dto: MDManga, builder: MangaDexRequestBuilder) -> MangaRef {
        var cover: URL?
        if let fileName = dto.relationships?.first(where: { $0.type == "cover_art" })?.attributes?.fileName {
            cover = builder.coverURL(mangaId: dto.id, fileName: fileName)
        }
        return MangaRef(sourceId: id, id: dto.id, title: Self.title(of: dto.attributes), coverURL: cover)
    }

    private static let titlePriority = ["zh", "zh-hk", "en", "ja-ro", "ja"]

    static func title(of attrs: MDMangaAttributes) -> String {
        var maps: [[String: String]] = []
        if let t = attrs.title { maps.append(t.values) }
        for alt in attrs.altTitles ?? [] { maps.append(alt.values) }
        for lang in titlePriority {
            for map in maps {
                if let value = map[lang], !value.isEmpty { return value }
            }
        }
        for map in maps {
            for key in map.keys.sorted() {
                if let value = map[key], !value.isEmpty { return value }
            }
        }
        return ""
    }

    /// First non-empty value by language priority, else any value (deterministic by key order).
    static func pick(_ map: [String: String]?, priority: [String]) -> String? {
        guard let map else { return nil }
        for lang in priority {
            if let value = map[lang], !value.isEmpty { return value }
        }
        for key in map.keys.sorted() {
            if let value = map[key], !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: - Chapters

    private struct ChapterEntry {
        var dto: MDChapter
        var label: String?
        var number: Double?
        var position: Int
    }

    static func buildChapters(_ items: [MDChapter], mangaId: String, sourceId: String, languages: [String]) -> [Chapter] {
        func rank(_ item: MDChapter) -> Int {
            languages.firstIndex(of: item.attributes.translatedLanguage ?? "") ?? languages.count
        }
        func isBetter(_ a: MDChapter, than b: MDChapter) -> Bool {
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.attributes.publishAt ?? "") < (b.attributes.publishAt ?? "")
        }

        // Keys: "n:<chapter>" for numbered groups, "o:<id>" for oneshots; first-seen order preserved.
        var order: [String] = []
        var best: [String: MDChapter] = [:]
        for item in items {
            if item.attributes.externalUrl != nil { continue }
            if item.attributes.pages == 0 { continue }
            let number = item.attributes.chapter?.trimmingCharacters(in: .whitespaces)
            if let number, !number.isEmpty {
                let key = "n:" + number
                if let current = best[key] {
                    if isBetter(item, than: current) { best[key] = item }
                } else {
                    best[key] = item
                    order.append(key)
                }
            } else {
                let key = "o:" + item.id
                best[key] = item
                order.append(key)
            }
        }

        var entries: [ChapterEntry] = []
        for (position, key) in order.enumerated() {
            guard let dto = best[key] else { continue }
            let label: String? = key.hasPrefix("n:") ? String(key.dropFirst(2)) : nil
            let number: Double? = label.flatMap { Double($0) }
            entries.append(ChapterEntry(dto: dto, label: label, number: number, position: position))
        }
        entries.sort { a, b in
            switch (a.number, b.number) {
            case let (x?, y?):
                if x != y { return x < y }
                return a.position < b.position
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.position < b.position
            }
        }

        var chapters: [Chapter] = []
        for (index, entry) in entries.enumerated() {
            var title = entry.label.map { "第 \($0) 话" } ?? "番外"
            if let extra = entry.dto.attributes.title, !extra.isEmpty {
                title += " · \(extra)"
            }
            chapters.append(Chapter(
                id: entry.dto.id,
                mangaId: mangaId,
                sourceId: sourceId,
                title: title,
                number: entry.number,
                index: index
            ))
        }
        return chapters
    }
}
