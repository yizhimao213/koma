import Foundation

public struct MangaRef: Hashable, Codable, Sendable {
    public var sourceId: String
    public var id: String
    public var title: String
    public var coverURL: URL?

    public init(sourceId: String, id: String, title: String, coverURL: URL? = nil) {
        self.sourceId = sourceId
        self.id = id
        self.title = title
        self.coverURL = coverURL
    }
}

public enum MangaStatus: String, Codable, Sendable {
    case ongoing, completed, unknown
}

public struct MangaDetails: Codable, Sendable {
    public var ref: MangaRef
    public var author: String?
    public var description: String?
    public var tags: [String]
    public var status: MangaStatus

    public init(
        ref: MangaRef,
        author: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        status: MangaStatus = .unknown
    ) {
        self.ref = ref
        self.author = author
        self.description = description
        self.tags = tags
        self.status = status
    }
}

public struct Chapter: Hashable, Codable, Sendable {
    public var id: String
    public var mangaId: String
    public var sourceId: String
    public var title: String
    public var number: Double?
    /// 0-based reading order within the manga.
    public var index: Int

    public init(id: String, mangaId: String, sourceId: String, title: String, number: Double? = nil, index: Int) {
        self.id = id
        self.mangaId = mangaId
        self.sourceId = sourceId
        self.title = title
        self.number = number
        self.index = index
    }
}

public struct PageRef: Hashable, Codable, Sendable {
    public var index: Int
    public var url: URL
    public var headers: [String: String]
    /// Alternate image host tried when `url` fails to load.
    public var fallbackURL: URL?

    public init(index: Int, url: URL, headers: [String: String] = [:], fallbackURL: URL? = nil) {
        self.index = index
        self.url = url
        self.headers = headers
        self.fallbackURL = fallbackURL
    }
}

public struct MangaPage: Sendable {
    public var items: [MangaRef]
    public var hasNextPage: Bool

    public init(items: [MangaRef], hasNextPage: Bool) {
        self.items = items
        self.hasNextPage = hasNextPage
    }
}
