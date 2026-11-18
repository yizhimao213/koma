import Foundation
import GRDB

/// Only holds a thread-safe GRDB `DatabaseWriter`.
public final class HistoryRepository: @unchecked Sendable {
    private let writer: DatabaseWriter
    private let coverResolver: CoverURLResolver

    public init(_ database: AppDatabase, coverResolver: CoverURLResolver = CoverURLResolver()) {
        self.writer = database.writer
        self.coverResolver = coverResolver
    }

    public func save(_ ref: MangaRef, progress: ReadingProgress) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO history (sourceId, mangaId, chapterId, pageIndex, pageCount, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(sourceId, mangaId) DO UPDATE SET
                    chapterId = excluded.chapterId,
                    pageIndex = excluded.pageIndex,
                    pageCount = excluded.pageCount,
                    updatedAt = excluded.updatedAt
                """, arguments: [
                    ref.sourceId, ref.id, progress.chapterId,
                    progress.pageIndex, progress.pageCount, progress.updatedAt
                ])
            try db.execute(
                sql: "UPDATE manga SET lastReadAt = ? WHERE sourceId = ? AND id = ?",
                arguments: [progress.updatedAt, ref.sourceId, ref.id])
            if progress.pageIndex == progress.pageCount - 1 {
                try db.execute(
                    sql: "UPDATE chapter SET isRead = 1 WHERE sourceId = ? AND mangaId = ? AND id = ?",
                    arguments: [ref.sourceId, ref.id, progress.chapterId])
            }
        }
    }

    public func progress(for ref: MangaRef) throws -> ReadingProgress? {
        try writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM history WHERE sourceId = ? AND mangaId = ?",
                arguments: [ref.sourceId, ref.id]
            ).map(HistoryRepository.progress(from:))
        }
    }

    public func recent(limit: Int) throws -> [(MangaRef, ReadingProgress)] {
        let resolver = coverResolver
        return try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT h.chapterId, h.pageIndex, h.pageCount, h.updatedAt,
                       m.sourceId, m.id, m.title, m.coverURL
                FROM history h
                JOIN manga m ON m.sourceId = h.sourceId AND m.id = h.mangaId
                ORDER BY h.updatedAt DESC
                LIMIT ?
                """, arguments: [limit])
            return rows.map { (MangaRef(row: $0, resolver: resolver), HistoryRepository.progress(from: $0)) }
        }
    }

    public func delete(_ ref: MangaRef) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM history WHERE sourceId = ? AND mangaId = ?",
                arguments: [ref.sourceId, ref.id])
        }
    }

    private static func progress(from row: Row) -> ReadingProgress {
        ReadingProgress(
            chapterId: row["chapterId"],
            pageIndex: row["pageIndex"],
            pageCount: row["pageCount"],
            updatedAt: row["updatedAt"])
    }
}
