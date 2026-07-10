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
    private let buildCancellation = IndexBuildCancellation()

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
        buildCancellation.cancel()
        buildTask = nil
        rootURL = url

        guard let url else {
            state = .unavailable
            return
        }

        state = .building
        let buildGeneration = buildCancellation.begin()
        buildTask = Task.detached(priority: .utility) { [weak self, buildCancellation] in
            guard let self else { return }
            let shouldCancel = { buildCancellation.isCancelled(buildGeneration) }
            do {
                try await self.runDatabaseOperation {
                    try Self.rebuildIndex(at: url, shouldCancel: shouldCancel)
                }
                guard !shouldCancel() else { return }
                await self.finishBuild(for: url)
            } catch is CancellationError {
            } catch {
                await self.failBuild(error, for: url)
            }
        }
    }

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

    private nonisolated static func rebuildIndex(at rootURL: URL, shouldCancel: @escaping @Sendable () -> Bool = { false }) throws {
        if shouldCancel() { throw CancellationError() }
        let dbURL = try prepareDatabaseURL(for: rootURL)
        let db = try openDatabase(at: dbURL)
        defer { sqlite3_close(db) }

        try execute(sql: "PRAGMA journal_mode=WAL;", db: db)
        try execute(sql: Self.schemaSQL, db: db)

        try execute(sql: "BEGIN;", db: db)
        do {
            try execute(sql: "INSERT INTO articles_fts(articles_fts) VALUES('delete-all');", db: db)
            try execute(sql: "DELETE FROM articles;", db: db)
            try indexFiles(in: rootURL, db: db, shouldCancel: shouldCancel)
            try execute(sql: "COMMIT;", db: db)
        } catch {
            try? execute(sql: "ROLLBACK;", db: db)
            throw error
        }
    }

    private nonisolated static func indexFiles(
        in rootURL: URL,
        db: OpaquePointer?,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws {
        let includeDependencyDirectories = UserDefaults.standard.bool(
            forKey: AppState.indexDependencyDirectoriesKey
        )
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ServiceError.invalidRoot
        }

        var articleStatement: OpaquePointer?
        defer { sqlite3_finalize(articleStatement) }
        try prepare(
            sql: "INSERT INTO articles(path, title, mtime) VALUES(?, ?, ?);",
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
            if shouldCancel() { throw CancellationError() }

            autoreleasepool {
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
                ) else { return }

                let name = fileURL.lastPathComponent
                if values.isDirectory == true {
                    if FileService.shouldSkipDirectory(
                        name: name,
                        includeDependencyDirectories: includeDependencyDirectories
                    ) {
                        enumerator.skipDescendants()
                    }
                    return
                }

                guard values.isRegularFile == true else { return }
                guard !FileService.shouldSkipIndexFile(name: name) else { return }
                guard FileService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { return }

                let fileSize = values.fileSize ?? 0
                guard fileSize > 0, fileSize <= FileService.maxWikiIndexFileBytes else { return }

                guard let body = readIndexableText(at: fileURL, expectedSize: fileSize) else { return }

                let title = extractTitle(from: body, fallback: name)
                let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0

                do {
                    sqlite3_reset(articleStatement)
                    sqlite3_clear_bindings(articleStatement)
                    try bind(text: fileURL.path, to: 1, statement: articleStatement)
                    try bind(text: title, to: 2, statement: articleStatement)
                    try bind(double: mtime, to: 3, statement: articleStatement)
                    try stepDone(statement: articleStatement, db: db)

                    let rowID = sqlite3_last_insert_rowid(db)

                    sqlite3_reset(ftsStatement)
                    sqlite3_clear_bindings(ftsStatement)
                    try bind(int64: rowID, to: 1, statement: ftsStatement)
                    try bind(text: title, to: 2, statement: ftsStatement)
                    try bind(text: body, to: 3, statement: ftsStatement)
                    try stepDone(statement: ftsStatement, db: db)
                } catch {
                    // 1 ファイルの失敗でインデックス全体を落とさない
                }
            }
        }
    }

    /// `String(contentsOf:)` の例外・巨大ファイル読み込みを避けて UTF-8 テキストを取得する。
    private nonisolated static func readIndexableText(at fileURL: URL, expectedSize: Int) -> String? {
        guard expectedSize <= FileService.maxWikiIndexFileBytes else { return nil }
        guard let data = try? Data(
            contentsOf: fileURL,
            options: [.mappedIfSafe, .uncached]
        ), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\"\"" }
        // CJK は unicode61 のトークン単位 AND 検索（フレーズ引用だとヒットしないことがある）
        if trimmed.unicodeScalars.contains(where: { $0.value > 0x7F }) {
            return trimmed
                .replacingOccurrences(of: "\"", with: "\"\"")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .joined(separator: " ")
        }
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private nonisolated static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    /// db キュー上でも参照できるビルド世代ベースのキャンセル判定。
    private final class IndexBuildCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var generation: UInt64 = 0
        private var cancelledGeneration: UInt64?

        func begin() -> UInt64 {
            lock.lock()
            generation += 1
            let current = generation
            cancelledGeneration = nil
            lock.unlock()
            return current
        }

        func cancel() {
            lock.lock()
            cancelledGeneration = generation
            lock.unlock()
        }

        func isCancelled(_ generation: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelledGeneration == generation
        }
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS articles (
      id INTEGER PRIMARY KEY,
      path TEXT UNIQUE NOT NULL,
      title TEXT,
      mtime REAL NOT NULL
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts USING fts5(
      title, body,
      content='articles',
      content_rowid='id',
      tokenize='unicode61'
    );
    """
}
