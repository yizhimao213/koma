import Foundation
import GRDB

/// Only holds a thread-safe GRDB `DatabaseWriter`.
public final class LibraryRepository: @unchecked Sendable {
    private let writer: DatabaseWriter
    private let coverResolver: CoverURLResolver

    public init(_ database: AppDatabase, coverResolver: CoverURLResolver = CoverURLResolver()) {
        self.writer = database.writer
        self.coverResolver = coverResolver
    }

    public func upsert(details: MangaDetails, chapters: [Chapter]) throws {
        let tagsData = try JSONEncoder().encode(details.tags)
        let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "[]"
        let storedCover = coverResolver.storedString(for: details.ref.coverURL)
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO manga (sourceId, id, title, coverURL, author, description, tags, status, inLibrary, addedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
                ON CONFLICT(sourceId, id) DO UPDATE SET
                    title = excluded.title,
                    coverURL = excluded.coverURL,
                    author = excluded.author,
                    description = excluded.description,
                    tags = excluded.tags,
                    status = excluded.status
                """, arguments: [
                    details.ref.sourceId, details.ref.id, details.ref.title,
                    storedCover, details.author, details.description,
                    tagsJSON, details.status.rawValue, Date()
                ])
            for chapter in chapters {
                try db.execute(sql: """
                    INSERT INTO chapter (sourceId, mangaId, id, title, number, idx, isRead)
                    VALUES (?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(sourceId, mangaId, id) DO UPDATE SET
                        title = excluded.title,
                        number = excluded.number,
                        idx = excluded.idx
                    """, arguments: [
                        chapter.sourceId, chapter.mangaId, chapter.id,
                        chapter.title, chapter.number, chapter.index
                    ])
            }
        }
    }

    public func setInLibrary(_ ref: MangaRef, _ value: Bool) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO manga (sourceId, id, title, coverURL, tags, status, inLibrary, addedAt)
                VALUES (?, ?, ?, ?, '[]', 'unknown', 0, ?)
                """, arguments: [ref.sourceId, ref.id, ref.title, coverResolver.storedString(for: ref.coverURL), Date()])
            if value {
                try db.execute(
                    sql: "UPDATE manga SET inLibrary = 1, addedAt = ? WHERE sourceId = ? AND id = ? AND inLibrary = 0",
                    arguments: [Date(), ref.sourceId, ref.id])
            } else {
                try db.execute(
                    sql: "UPDATE manga SET inLibrary = 0 WHERE sourceId = ? AND id = ?",
                    arguments: [ref.sourceId, ref.id])
            }
        }
    }

    public func items(categoryId: Int64?, sort: LibrarySort) throws -> [LibraryEntry] {
        let resolver = coverResolver
        return try writer.read { db in
            try LibraryRepository.fetchItems(db, categoryId: categoryId, sort: sort, resolver: resolver)
        }
    }

    public func observeItems(categoryId: Int64?, sort: LibrarySort) -> AsyncStream<[LibraryEntry]> {
        let reader: DatabaseReader = writer
        let resolver = coverResolver
        return AsyncStream { continuation in
            let observation = ValueObservation
                .tracking { db in
                    try LibraryRepository.fetchItems(db, categoryId: categoryId, sort: sort, resolver: resolver)
                }
                .removeDuplicates()
            let cancellable = observation.start(
                in: reader,
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    public func categories() throws -> [CategoryRecord] {
        try writer.read { db in
            try CategoryRecord.fetchAll(db, sql: "SELECT * FROM category ORDER BY sortOrder, id")
        }
    }

    public func addCategory(name: String) throws {
        try writer.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM category") ?? 0
            try db.execute(
                sql: "INSERT INTO category (name, sortOrder) VALUES (?, ?)",
                arguments: [name, next])
        }
    }

    public func assign(_ ref: MangaRef, to categoryIds: [Int64]) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM manga_category WHERE sourceId = ? AND mangaId = ?",
                arguments: [ref.sourceId, ref.id])
            for categoryId in categoryIds {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO manga_category (sourceId, mangaId, categoryId) VALUES (?, ?, ?)",
                    arguments: [ref.sourceId, ref.id, categoryId])
            }
        }
    }

    public func chapters(for ref: MangaRef) throws -> [Chapter] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chapter WHERE sourceId = ? AND mangaId = ? ORDER BY idx
                """, arguments: [ref.sourceId, ref.id])
            return rows.map { row in
                Chapter(
                    id: row["id"],
                    mangaId: row["mangaId"],
                    sourceId: row["sourceId"],
                    title: row["title"],
                    number: row["number"],
                    index: row["idx"])
            }
        }
    }

    /// Ids of all read chapters of a manga, in one query.
    public func readChapterIds(for ref: MangaRef) throws -> Set<String> {
        try writer.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT id FROM chapter WHERE sourceId = ? AND mangaId = ? AND isRead = 1",
                arguments: [ref.sourceId, ref.id]))
        }
    }

    public func isInLibrary(_ ref: MangaRef) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT inLibrary FROM manga WHERE sourceId = ? AND id = ?",
                arguments: [ref.sourceId, ref.id]) ?? false
        }
    }

    public func isRead(_ chapter: Chapter) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT isRead FROM chapter WHERE sourceId = ? AND mangaId = ? AND id = ?",
                arguments: [chapter.sourceId, chapter.mangaId, chapter.id]) ?? false
        }
    }

    public func markRead(_ chapters: [Chapter], _ read: Bool) throws {
        try writer.write { db in
            for chapter in chapters {
                try db.execute(
                    sql: "UPDATE chapter SET isRead = ? WHERE sourceId = ? AND mangaId = ? AND id = ?",
                    arguments: [read, chapter.sourceId, chapter.mangaId, chapter.id])
            }
        }
    }

    public func remove(_ ref: MangaRef) throws {
        try writer.write { db in
            let args: StatementArguments = [ref.sourceId, ref.id]
            try db.execute(sql: "DELETE FROM chapter WHERE sourceId = ? AND mangaId = ?", arguments: args)
            try db.execute(sql: "DELETE FROM manga_category WHERE sourceId = ? AND mangaId = ?", arguments: args)
            try db.execute(sql: "DELETE FROM history WHERE sourceId = ? AND mangaId = ?", arguments: args)
            try db.execute(sql: "DELETE FROM manga WHERE sourceId = ? AND id = ?", arguments: args)
        }
    }

    static func fetchItems(_ db: Database, categoryId: Int64?, sort: LibrarySort, resolver: CoverURLResolver) throws -> [LibraryEntry] {
        var sql = """
            SELECT m.sourceId, m.id, m.title, m.coverURL, m.lastReadAt,
                (SELECT COUNT(*) FROM chapter c
                 WHERE c.sourceId = m.sourceId AND c.mangaId = m.id AND c.isRead = 0) AS unreadCount
            FROM manga m
            WHERE m.inLibrary = 1
            """
        var arguments = StatementArguments()
        if let categoryId {
            sql += """

                AND EXISTS (SELECT 1 FROM manga_category mc
                            WHERE mc.sourceId = m.sourceId AND mc.mangaId = m.id AND mc.categoryId = ?)
                """
            arguments += [categoryId]
        }
        switch sort {
        case .lastRead:
            sql += " ORDER BY (m.lastReadAt IS NULL), m.lastReadAt DESC, m.addedAt DESC"
        case .added:
            sql += " ORDER BY m.addedAt DESC"
        case .unread:
            sql += " ORDER BY unreadCount DESC, m.addedAt DESC"
        case .title:
            break
        }
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        var items = rows.map { row -> LibraryEntry in
            LibraryEntry(ref: MangaRef(row: row, resolver: resolver), unreadCount: row["unreadCount"], lastReadAt: row["lastReadAt"])
        }
        if sort == .title {
            items.sort { $0.ref.title.localizedCaseInsensitiveCompare($1.ref.title) == .orderedAscending }
        }
        return items
    }
}
