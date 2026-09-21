import Foundation
import SQLite3
import CryptoKit

public enum ClipStoreError: Error {
    case openFailed(String)
    case sqlFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local SQLite history. Newest-first reads; unlimited retention; consecutive duplicates collapse.
public final class ClipStore {
    private var db: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw ClipStoreError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT,
                data BLOB,
                hash TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS items_created ON items(created_at DESC, id DESC);
            """)
    }

    deinit { sqlite3_close(db) }

    public static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipbook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite").path
    }

    /// Returns the inserted item, or nil when it duplicates the newest item.
    @discardableResult
    public func insert(_ payload: ClipPayload, at date: Date = Date()) throws -> ClipItem? {
        let (kind, text, data) = Self.columns(for: payload)
        let hash = Self.hash(kind: kind, text: text, data: data)

        if try newestHash() == hash { return nil }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare("INSERT INTO items (kind, text, data, hash, created_at) VALUES (?,?,?,?,?)", &stmt)
        sqlite3_bind_text(stmt, 1, kind, -1, SQLITE_TRANSIENT)
        if let text { sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 2) }
        if let data {
            _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, hash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, date.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw ClipStoreError.sqlFailed(lastError) }
        return ClipItem(id: sqlite3_last_insert_rowid(db), payload: payload, createdAt: date)
    }

    /// Newest first.
    public func fetch(limit: Int, offset: Int = 0) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare("SELECT id, kind, text, data, created_at FROM items ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?", &stmt)
        sqlite3_bind_int64(stmt, 1, Int64(limit))
        sqlite3_bind_int64(stmt, 2, Int64(offset))
        var items: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let kind = String(cString: sqlite3_column_text(stmt, 1))
            let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            var data: Data?
            if let blob = sqlite3_column_blob(stmt, 3) {
                data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 3)))
            }
            let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            if let payload = Self.payload(kind: kind, text: text, data: data) {
                items.append(ClipItem(id: id, payload: payload, createdAt: date))
            }
        }
        return items
    }

    public func count() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare("SELECT COUNT(*) FROM items", &stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw ClipStoreError.sqlFailed(lastError) }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    public func clear() throws {
        try exec("DELETE FROM items; VACUUM;")
    }

    // MARK: - Internals

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw ClipStoreError.sqlFailed(lastError) }
    }

    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { throw ClipStoreError.sqlFailed(lastError) }
    }

    private func newestHash() throws -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare("SELECT hash FROM items ORDER BY created_at DESC, id DESC LIMIT 1", &stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    private static func columns(for payload: ClipPayload) -> (String, String?, Data?) {
        switch payload {
        case .text(let s): return ("text", s, nil)
        case .image(let d): return ("image", nil, d)
        case .files(let paths): return ("files", paths.joined(separator: "\n"), nil)
        }
    }

    private static func payload(kind: String, text: String?, data: Data?) -> ClipPayload? {
        switch kind {
        case "text": return text.map { .text($0) }
        case "image": return data.map { .image($0) }
        case "files": return text.map { .files($0.components(separatedBy: "\n")) }
        default: return nil
        }
    }

    private static func hash(kind: String, text: String?, data: Data?) -> String {
        var h = SHA256()
        h.update(data: Data(kind.utf8))
        if let text { h.update(data: Data(text.utf8)) }
        if let data { h.update(data: data) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
