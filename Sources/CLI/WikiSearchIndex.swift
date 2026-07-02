import Foundation
import SQLite3

final class WikiSearchIndex {
    struct Hit: Equatable, Sendable {
        let path: String
        let title: String
        let snippet: String
        let bm25Rank: Double
    }

    private enum IndexError: LocalizedError {
        case invalidRoot
        case databaseOpenFailed(String)
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .invalidRoot:
                return "Invalid vault root."
            case .databaseOpenFailed(let message):
                return "Failed to open index database: \(message)"
            case .sqlite(let message):
                return message
            }
        }
    }

    private let vaultRoot: URL
    private let databaseURL: URL

    init(vaultRoot: URL) throws {
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.databaseURL = try Self.prepareDatabaseURL(for: self.vaultRoot)

        let db = try Self.openDatabase(at: databaseURL)
        defer { sqlite3_close(db) }

        try Self.execute(sql: "PRAGMA journal_mode=WAL;", db: db)
        try Self.migrateSchemaIfNeeded(db: db)
        try Self.execute(sql: Self.schemaSQL, db: db)
    }

    func rebuildIfNeeded() throws {
        let files = try MCPToolSupport.listMarkdownFiles(in: vaultRoot)
        let dbMTime = Self.modificationTime(for: databaseURL)

        if try Self.isIndexEmpty(databaseURL: databaseURL) || files.contains(where: { Self.modificationTime(for: $0) > dbMTime }) {
            try rebuild(with: files)
        }
    }

    func search(query: String, limit: Int) throws -> [Hit] {
        let db = try Self.openDatabase(at: databaseURL)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        try Self.prepare(
            sql: """
            SELECT articles.path,
                   COALESCE(articles.title, ''),
                   snippet(articles_fts, 1, '<<', '>>', '...', 16),
                   bm25(articles_fts)
            FROM articles_fts
            JOIN articles ON articles.id = articles_fts.rowid
            WHERE articles_fts MATCH ?
            ORDER BY bm25(articles_fts) ASC
            LIMIT ?;
            """,
            db: db,
            statement: &statement
        )

        try Self.bind(text: Self.quotedQuery(query), to: 1, statement: statement)
        try Self.bind(int32: Int32(limit), to: 2, statement: statement)

        var hits: [Hit] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                guard let path = Self.columnText(at: 0, statement: statement) else { continue }
                let title = Self.columnText(at: 1, statement: statement) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let snippet = Self.columnText(at: 2, statement: statement) ?? ""
                let rank = sqlite3_column_double(statement, 3)
                hits.append(Hit(path: path, title: title, snippet: snippet, bm25Rank: rank))
            } else if result == SQLITE_DONE {
                return hits
            } else {
                throw Self.sqliteError(from: db)
            }
        }
    }

    private func rebuild(with files: [URL]) throws {
        let db = try Self.openDatabase(at: databaseURL)
        defer { sqlite3_close(db) }

        try Self.execute(sql: "PRAGMA journal_mode=WAL;", db: db)
        try Self.execute(sql: Self.schemaSQL, db: db)

        try Self.execute(sql: "BEGIN;", db: db)
        do {
            try Self.execute(sql: "INSERT INTO articles_fts(articles_fts) VALUES('delete-all');", db: db)
            try Self.execute(sql: "DELETE FROM articles;", db: db)
            try Self.index(files: files, rootURL: vaultRoot, db: db)
            try Self.execute(sql: "COMMIT;", db: db)
        } catch {
            try? Self.execute(sql: "ROLLBACK;", db: db)
            throw error
        }
    }

    private static func index(files: [URL], rootURL: URL, db: OpaquePointer?) throws {
        var articleStatement: OpaquePointer?
        defer { sqlite3_finalize(articleStatement) }
        try prepare(
            sql: "INSERT INTO articles(path, title, body, mtime) VALUES(?, ?, ?, ?);",
            db: db,
            statement: &articleStatement
        )

        var ftsStatement: OpaquePointer?
        defer { sqlite3_finalize(ftsStatement) }
        try prepare(
            sql: "INSERT INTO articles_fts(rowid, title, body) VALUES(?, ?, ?);",
            db: db,
            statement: &ftsStatement
        )

        for fileURL in files {
            let note = try MCPToolSupport.loadNote(at: fileURL)
            let relativePath = MCPToolSupport.relativePath(for: fileURL, root: rootURL)
            let mtime = modificationTime(for: fileURL)

            sqlite3_reset(articleStatement)
            sqlite3_clear_bindings(articleStatement)
            try bind(text: relativePath, to: 1, statement: articleStatement)
            try bind(text: note.title, to: 2, statement: articleStatement)
            try bind(text: note.body, to: 3, statement: articleStatement)
            try bind(double: mtime, to: 4, statement: articleStatement)
            try stepDone(statement: articleStatement, db: db)

            let rowID = sqlite3_last_insert_rowid(db)

            sqlite3_reset(ftsStatement)
            sqlite3_clear_bindings(ftsStatement)
            try bind(int64: rowID, to: 1, statement: ftsStatement)
            try bind(text: note.title, to: 2, statement: ftsStatement)
            try bind(text: note.body, to: 3, statement: ftsStatement)
            try stepDone(statement: ftsStatement, db: db)
        }
    }

    private static func isIndexEmpty(databaseURL: URL) throws -> Bool {
        let db = try openDatabase(at: databaseURL)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        try prepare(
            sql: "SELECT COUNT(*) FROM articles;",
            db: db,
            statement: &statement
        )

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(from: db)
        }

        return sqlite3_column_int64(statement, 0) == 0
    }

    private static func prepareDatabaseURL(for rootURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IndexError.invalidRoot
        }

        let supportDirectory = rootURL.appendingPathComponent(".kobaamd", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        return supportDirectory.appendingPathComponent("index.sqlite")
    }

    private static func modificationTime(for url: URL) -> Double {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }

    private static func openDatabase(at url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open(url.path, &db)
        guard result == SQLITE_OK, db != nil else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
            if let db {
                sqlite3_close(db)
            }
            throw IndexError.databaseOpenFailed(message)
        }
        return db
    }

    private static func execute(sql: String, db: OpaquePointer?) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite exec failed."
            sqlite3_free(errorPointer)
            throw IndexError.sqlite(message)
        }
    }

    private static func prepare(sql: String, db: OpaquePointer?, statement: inout OpaquePointer?) throws {
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw sqliteError(from: db)
        }
    }

    private static func bind(text: String, to index: Int32, statement: OpaquePointer?) throws {
        let result = text.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transientDestructor)
        }
        guard result == SQLITE_OK else {
            throw IndexError.sqlite("Failed to bind text parameter.")
        }
    }

    private static func bind(double: Double, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_double(statement, index, double)
        guard result == SQLITE_OK else {
            throw IndexError.sqlite("Failed to bind double parameter.")
        }
    }

    private static func bind(int64: Int64, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int64(statement, index, int64)
        guard result == SQLITE_OK else {
            throw IndexError.sqlite("Failed to bind int64 parameter.")
        }
    }

    private static func bind(int32: Int32, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int(statement, index, int32)
        guard result == SQLITE_OK else {
            throw IndexError.sqlite("Failed to bind integer parameter.")
        }
    }

    private static func stepDone(statement: OpaquePointer?, db: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteError(from: db)
        }
    }

    private static func columnText(at index: Int32, statement: OpaquePointer?) -> String? {
        guard let textPointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: textPointer)
    }

    private static func sqliteError(from db: OpaquePointer?) -> IndexError {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error."
        return .sqlite(message)
    }

    private static func quotedQuery(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Drops the FTS index and articles table if the stored schema is missing the `body` column or
    /// uses the `unicode61` tokenizer (which cannot index CJK text).  The next `schemaSQL` run will
    /// recreate both tables with the correct layout.
    private static func migrateSchemaIfNeeded(db: OpaquePointer?) throws {
        // Check whether the articles table has a body column.
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let r = sqlite3_prepare_v2(db, "PRAGMA table_info(articles);", -1, &stmt, nil)
        guard r == SQLITE_OK else { return }

        var hasBodyColumn = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == "body" {
                hasBodyColumn = true
            }
        }

        if !hasBodyColumn {
            // Old schema detected: drop both tables so schemaSQL recreates them cleanly.
            try execute(sql: "DROP TABLE IF EXISTS articles_fts;", db: db)
            try execute(sql: "DROP TABLE IF EXISTS articles;", db: db)
        }
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS articles (
      id INTEGER PRIMARY KEY,
      path TEXT UNIQUE NOT NULL,
      title TEXT,
      body TEXT,
      mtime REAL NOT NULL
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts USING fts5(
      title, body,
      content='articles',
      content_rowid='id',
      tokenize='trigram'
    );
    """
}
