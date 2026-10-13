import Foundation
import CSQLite

public struct Revision: Identifiable, Sendable {
    public let id: Int64
    public let date: Date
    public let reason: String
    public let project: StoryProject
}

/// One owner (the main actor in the app) serializes all access. WAL and FULL
/// synchronous commits protect accepted edits across application crashes.
public final class ProjectDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(url: URL, readOnly: Bool = false) throws {
        if !readOnly { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let flags = (readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        // Standalone backup snapshots must not create or depend on WAL sidecars.
        let filename = readOnly ? url.absoluteString + "?immutable=1" : url.path
        guard sqlite3_open_v2(filename, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle); handle = nil
            throw FolioError.database("Could not open your project library.")
        }
        var initialized = false
        defer { if !initialized { sqlite3_close(handle); handle = nil } }
        sqlite3_busy_timeout(handle, 1000)
        if !readOnly {
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
        try execute("CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, document BLOB NOT NULL, updated REAL NOT NULL); CREATE TABLE IF NOT EXISTS revisions (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE, document BLOB NOT NULL, created REAL NOT NULL, reason TEXT NOT NULL); CREATE INDEX IF NOT EXISTS revision_project ON revisions(project_id, created DESC); CREATE TABLE IF NOT EXISTS embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL);")
        try execute("PRAGMA user_version=1;")
        }
        let check = try statement("PRAGMA quick_check")
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW,
              let message = sqlite3_column_text(check, 0), String(cString: message) == "ok" else { throw FolioError.database("The library integrity check failed. Restore a backup; the original files are preserved.") }
        initialized = true
    }
    deinit { sqlite3_close(handle) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> FolioError { .database(String(cString: sqlite3_errmsg(handle))) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &result, nil) == SQLITE_OK, let result else { throw failure() }
        return result
    }
    private func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) { sqlite3_bind_text(stmt, index, value, -1, transient) }
    private func bind(_ value: Data, to stmt: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(value.count), transient) }
    }
    private func data(_ stmt: OpaquePointer, _ column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(stmt, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(stmt, column)))
    }
    public func projects() throws -> [StoryProject] {
        let stmt = try statement("SELECT id,document FROM projects ORDER BY updated DESC")
        defer { sqlite3_finalize(stmt) }
        var result: [StoryProject] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            let project = try JSONDecoder().decode(StoryProject.self, from: data(stmt, 1))
            try project.validate()
            guard let rawID = sqlite3_column_text(stmt, 0), UUID(uuidString: String(cString: rawID)) == project.id, !result.contains(where: { $0.id == project.id }) else { throw FolioError.invalidProject }
            result.append(project)
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return result
    }
    public func save(_ project: StoryProject, reason: String? = nil) throws {
        try project.validate()
        let document = try JSONEncoder().encode(project)
        try execute("BEGIN IMMEDIATE")
        do {
            let stmt = try statement("INSERT INTO projects(id,document,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET document=excluded.document,updated=excluded.updated")
            defer { sqlite3_finalize(stmt) }
            bind(project.id.uuidString, to: stmt, at: 1); bind(document, to: stmt, at: 2)
            sqlite3_bind_double(stmt, 3, project.updatedAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
            if let reason {
                let revision = try statement("INSERT INTO revisions(project_id,document,created,reason) VALUES(?,?,?,?)")
                defer { sqlite3_finalize(revision) }
                bind(project.id.uuidString, to: revision, at: 1); bind(document, to: revision, at: 2)
                sqlite3_bind_double(revision, 3, Date().timeIntervalSince1970); bind(reason, to: revision, at: 4)
                guard sqlite3_step(revision) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func revisions(projectID: UUID) throws -> [Revision] {
        let stmt = try statement("SELECT id,document,created,reason FROM revisions WHERE project_id=? ORDER BY id DESC LIMIT 100")
        defer { sqlite3_finalize(stmt) }
        bind(projectID.uuidString, to: stmt, at: 1)
        var output: [Revision] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            output.append(Revision(id: sqlite3_column_int64(stmt, 0), date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), reason: String(cString: sqlite3_column_text(stmt, 3)), project: try JSONDecoder().decode(StoryProject.self, from: data(stmt, 1))))
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return output
    }
    public func embedding(key: String) throws -> [Float]? {
        let stmt = try statement("SELECT vector FROM embeddings WHERE key=?")
        defer { sqlite3_finalize(stmt) }; bind(key, to: stmt, at: 1)
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw failure() }
        return try JSONDecoder().decode([Float].self, from: data(stmt, 0))
    }
    public func saveEmbedding(key: String, vector: [Float]) throws {
        let stmt = try statement("INSERT OR REPLACE INTO embeddings(key,vector) VALUES(?,?)")
        defer { sqlite3_finalize(stmt) }; bind(key, to: stmt, at: 1); bind(try JSONEncoder().encode(vector), to: stmt, at: 2)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    public func backup(to url: URL) throws {
        if let path = sqlite3_db_filename(handle, "main"), URL(fileURLWithPath: String(cString: path)).standardizedFileURL == url.standardizedFileURL { throw FolioError.database("Choose a backup location outside the active library file.") }
        var destination: OpaquePointer?
        guard sqlite3_open(url.path, &destination) == SQLITE_OK else { sqlite3_close(destination); throw FolioError.database("Could not create a backup.") }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", handle, "main") else { throw failure() }
        let status = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE && finished == SQLITE_OK else { throw FolioError.database("The backup could not finish. Please try again.") }
    }
}
