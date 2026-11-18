import Foundation
import GRDB

public struct CategoryRecord: Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "category"

    public var id: Int64?
    public var name: String
    public var sortOrder: Int

    public init(id: Int64? = nil, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        sortOrder = row["sortOrder"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["sortOrder"] = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum LibrarySort: Sendable {
    case lastRead, added, title, unread
}

public struct LibraryItem: Identifiable, Sendable {
    public var ref: MangaRef
    public var unreadCount: Int
    public var lastReadAt: Date?

    public var id: String { "\(ref.sourceId)/\(ref.id)" }

    public init(ref: MangaRef, unreadCount: Int, lastReadAt: Date? = nil) {
        self.ref = ref
        self.unreadCount = unreadCount
        self.lastReadAt = lastReadAt
    }
}

public struct ReadingProgress: Equatable, Sendable {
    public var chapterId: String
    public var pageIndex: Int
    public var pageCount: Int
    public var updatedAt: Date

    public init(chapterId: String, pageIndex: Int, pageCount: Int, updatedAt: Date = Date()) {
        self.chapterId = chapterId
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.updatedAt = updatedAt
    }
}

extension MangaRef {
    init(row: Row) {
        let cover: String? = row["coverURL"]
        self.init(
            sourceId: row["sourceId"],
            id: row["id"],
            title: row["title"],
            coverURL: cover.flatMap { URL(string: $0) }
        )
    }
}
