import Foundation
import SQLite3

@MainActor
final class WikiIndexService {
    enum IndexState: Equatable {
        case unavailable
        case building
        case ready
        case failed(String)
    }

    struct Hit: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        let fileName: String
        let title: String
        let snippet: String
        let bm25Rank: Double
    }

    private enum ServiceError: LocalizedError {
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

    private(set) var state: IndexState = .unavailable
    private(set) var rootURL: URL?

    private let dbQueue = DispatchQueue(label: "WikiIndexService.db")
    private var buildTask: Task<Void, Never>?

    func setRoot(_ url: URL?, force: Bool = false) {
        if !force, rootURL == url {
            switch state {
            case .ready, .building:
                return
            case .unavailable, .failed:
                break
            }
        }

        buildTask?.cancel()
        buildTask = nil
        rootURL = url

        guard let url else {
            state = .unavailable
            return
        }

        state = .building
        buildTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await self.runDatabaseOperation {
                    try Self.rebuildIndex(at: url)
                }
                guard !Task.isCancelled else { return }
                await self.finishBuild(for: url)
            } catch is CancellationError {
            } catch {
                await self.failBuild(error, for: url)
            }
        }
    }

    /// Returns matching index hits for *query*, or `nil` if the index is not ready.
    /// The FTS index uses the `trigram` tokenizer, so queries shorter than 3 characters
    /// will return no matches even when the query text appears in indexed files.
    func search(query: String, limit: Int = 100) async -> [Hit]? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard state == .ready, let rootURL else { return nil }

        do {
            return try await runDatabaseOperation {
                try Self.performSearch(rootURL: rootURL, query: trimmedQuery, limit: max(1, limit))
            }
        } catch {
            state = .failed(Self.message(for: error))
            return nil
        }
    }

    private func finishBuild(for url: URL) {
        guard rootURL == url else { return }
        state = .ready
    }

    private func failBuild(_ error: Error, for url: URL) {
        guard rootURL == url else { return }
        state = .failed(Self.message(for: error))
    }

    private func runDatabaseOperation<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func rebuildIndex(at rootURL: URL) throws {
        try Task.checkCancellation()
        let dbURL = try prepareDatabaseURL(for: rootURL)
        let db = try openDatabase(at: dbURL)
        defer { sqlite3_close(db) }

        try execute(sql: "PRAGMA journal_mode=WAL;", db: db)
        try migrateSchemaIfNeeded(db: db)
        try execute(sql: Self.schemaSQL, db: db)

        try execute(sql: "BEGIN;", db: db)
        do {
            try execute(sql: "INSERT INTO articles_fts(articles_fts) VALUES('delete-all');", db: db)
            try execute(sql: "DELETE FROM articles;", db: db)
            try indexFiles(in: rootURL, db: db)
            try execute(sql: "COMMIT;", db: db)
        } catch {
            try? execute(sql: "ROLLBACK;", db: db)
            throw error
        }
    }

    private nonisolated static func indexFiles(in rootURL: URL, db: OpaquePointer?) throws {
        let includeDependencyDirectories = UserDefaults.standard.bool(
            forKey: AppState.indexDependencyDirectoriesKey
        )
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ServiceError.invalidRoot
        }

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

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
            )
            if values?.isDirectory == true {
                if FileService.shouldSkipDirectory(
                    name: fileURL.lastPathComponent,
                    includeDependencyDirectories: includeDependencyDirectories
                ) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            guard FileService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard let body = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let title = extractTitle(from: body, fallback: fileURL.lastPathComponent)
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

            sqlite3_reset(articleStatement)
            sqlite3_clear_bindings(articleStatement)
            try bind(text: fileURL.path, to: 1, statement: articleStatement)
            try bind(text: title, to: 2, statement: articleStatement)
            try bind(text: body, to: 3, statement: articleStatement)
            try bind(double: mtime, to: 4, statement: articleStatement)
            try stepDone(statement: articleStatement, db: db)

            let rowID = sqlite3_last_insert_rowid(db)

            sqlite3_reset(ftsStatement)
            sqlite3_clear_bindings(ftsStatement)
            try bind(int64: rowID, to: 1, statement: ftsStatement)
            try bind(text: title, to: 2, statement: ftsStatement)
            try bind(text: body, to: 3, statement: ftsStatement)
            try stepDone(statement: ftsStatement, db: db)
        }
    }

    private nonisolated static func performSearch(rootURL: URL, query: String, limit: Int) throws -> [Hit] {
        let dbURL = try prepareDatabaseURL(for: rootURL)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ServiceError.databaseOpenFailed("Index database does not exist.")
        }

        let db = try openDatabase(at: dbURL)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        try prepare(
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

        try bind(text: quotedQuery(query), to: 1, statement: statement)
        try bind(int32: Int32(limit), to: 2, statement: statement)

        var hits: [Hit] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                guard let path = columnText(at: 0, statement: statement) else { continue }
                let title = columnText(at: 1, statement: statement) ?? URL(fileURLWithPath: path).lastPathComponent
                let snippet = columnText(at: 2, statement: statement) ?? ""
                let rank = sqlite3_column_double(statement, 3)
                let fileURL = URL(fileURLWithPath: path)
                hits.append(Hit(
                    id: UUID(),
                    fileURL: fileURL,
                    fileName: fileURL.lastPathComponent,
                    title: title,
                    snippet: snippet,
                    bm25Rank: rank
                ))
            } else if result == SQLITE_DONE {
                return hits
            } else {
                throw sqliteError(from: db)
            }
        }
    }

    private nonisolated static func prepareDatabaseURL(for rootURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ServiceError.invalidRoot
        }

        let supportDirectory = rootURL.appendingPathComponent(".kobaamd", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        return supportDirectory.appendingPathComponent("index.sqlite")
    }

    private nonisolated static func openDatabase(at url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open(url.path, &db)
        guard result == SQLITE_OK, db != nil else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
            if let db {
                sqlite3_close(db)
            }
            throw ServiceError.databaseOpenFailed(message)
        }
        return db
    }

    private nonisolated static func execute(sql: String, db: OpaquePointer?) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite exec failed."
            sqlite3_free(errorPointer)
            throw ServiceError.sqlite(message)
        }
    }

    private nonisolated static func prepare(sql: String, db: OpaquePointer?, statement: inout OpaquePointer?) throws {
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw sqliteError(from: db)
        }
    }

    private nonisolated static func bind(text: String, to index: Int32, statement: OpaquePointer?) throws {
        let result = text.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transientDestructor)
        }
        guard result == SQLITE_OK else {
            throw ServiceError.sqlite("Failed to bind text parameter.")
        }
    }

    private nonisolated static func bind(double: Double, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_double(statement, index, double)
        guard result == SQLITE_OK else {
            throw ServiceError.sqlite("Failed to bind double parameter.")
        }
    }

    private nonisolated static func bind(int64: Int64, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int64(statement, index, int64)
        guard result == SQLITE_OK else {
            throw ServiceError.sqlite("Failed to bind int64 parameter.")
        }
    }

    private nonisolated static func bind(int32: Int32, to index: Int32, statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int(statement, index, int32)
        guard result == SQLITE_OK else {
            throw ServiceError.sqlite("Failed to bind integer parameter.")
        }
    }

    private nonisolated static func stepDone(statement: OpaquePointer?, db: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteError(from: db)
        }
    }

    private nonisolated static func columnText(at index: Int32, statement: OpaquePointer?) -> String? {
        guard let textPointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: textPointer)
    }

    private nonisolated static func sqliteError(from db: OpaquePointer?) -> ServiceError {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error."
        return .sqlite(message)
    }

    private nonisolated static func extractTitle(from body: String, fallback: String) -> String {
        for line in body.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("# ") else { continue }
            let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? fallback : title
        }
        return fallback
    }

    private nonisolated static func quotedQuery(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private nonisolated static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    /// Drops the FTS index and articles table when the stored schema is missing the `body` column
    /// (old layout that pre-dates the trigram tokenizer migration).  The next `schemaSQL` run will
    /// recreate both tables with the correct layout.
    private nonisolated static func migrateSchemaIfNeeded(db: OpaquePointer?) throws {
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
