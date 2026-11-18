import Foundation
import GRDB

public final class AppDatabase {
    public let writer: DatabaseWriter

    private init(writer: DatabaseWriter) throws {
        self.writer = writer
        try AppDatabase.migrator.migrate(writer)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        try AppDatabase(writer: DatabasePool(path: url.path))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE manga (
                    sourceId TEXT NOT NULL,
                    id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    coverURL TEXT,
                    author TEXT,
                    description TEXT,
                    tags TEXT NOT NULL DEFAULT '[]',
                    status TEXT NOT NULL DEFAULT 'unknown',
                    inLibrary BOOLEAN NOT NULL DEFAULT 0,
                    addedAt DATETIME NOT NULL,
                    lastReadAt DATETIME,
                    PRIMARY KEY (sourceId, id)
                );
                CREATE TABLE chapter (
                    sourceId TEXT NOT NULL,
                    mangaId TEXT NOT NULL,
                    id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    number DOUBLE,
                    idx INTEGER NOT NULL,
                    isRead BOOLEAN NOT NULL DEFAULT 0,
                    PRIMARY KEY (sourceId, mangaId, id)
                );
                CREATE TABLE category (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    sortOrder INTEGER NOT NULL
                );
                CREATE TABLE manga_category (
                    sourceId TEXT NOT NULL,
                    mangaId TEXT NOT NULL,
                    categoryId INTEGER NOT NULL,
                    PRIMARY KEY (sourceId, mangaId, categoryId)
                );
                CREATE TABLE history (
                    sourceId TEXT NOT NULL,
                    mangaId TEXT NOT NULL,
                    chapterId TEXT NOT NULL,
                    pageIndex INTEGER NOT NULL,
                    pageCount INTEGER NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    PRIMARY KEY (sourceId, mangaId)
                );
                INSERT INTO category (name, sortOrder) VALUES ('在追', 0);
                INSERT INTO category (name, sortOrder) VALUES ('已完结', 1);
                """)
        }
        return migrator
    }
}
