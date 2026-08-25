import Foundation
import SQLite3

/// How much was written in a window, and how much of it was wrong.
public struct CheckCounts: Sendable, Equatable {
    public let checked: Int
    public let withMistake: Int

    public init(checked: Int, withMistake: Int) {
        self.checked = checked
        self.withMistake = withMistake
    }
}

public enum MistakeStoreError: Error, Equatable {
    case couldNotOpen(String)
    case couldNotPrepare(String)
    case couldNotWrite(String)
}

/// The mistake log: every verdict this app has ever produced, on disk.
///
/// An `actor` rather than a struct with a lock, because the `sqlite3` handle is
/// an `OpaquePointer` and therefore not `Sendable`. Actor isolation is the one
/// way to hold it that Swift 6 accepts without `@unchecked`, and it has the
/// property this app actually needs: the write never runs on the `@MainActor`
/// the check pipeline lives on, so recording a mistake cannot add a millisecond
/// to the popup.
///
/// Correct sentences are counted, never stored. That is the difference between a
/// log of your mistakes and a log of your writing, and it is the reason there
/// are two tables instead of one.
public actor MistakeStore {

    /// Owns the open connection, purely so something with an ordinary `deinit`
    /// can close it.
    ///
    /// An actor's `deinit` is nonisolated and may not touch a non-Sendable
    /// stored property, and `isolated deinit`, which exists for exactly this,
    /// makes the whole-module release build fail with "circular reference" while
    /// the debug build succeeds. A plain final class has no such problem: it is
    /// held as actor-isolated state, so it never escapes, and it closes the
    /// handle when the store goes away.
    private final class Handle {
        let pointer: OpaquePointer

        init(pointer: OpaquePointer) { self.pointer = pointer }

        deinit { sqlite3_close_v2(pointer) }
    }

    /// Beside `diagnostics.log`, because everything this app writes belongs in
    /// one directory you can delete in one gesture.
    public nonisolated static let defaultURL = URL.applicationSupportDirectory
        .appending(path: "kibitz", directoryHint: .isDirectory)
        .appending(path: "mistakes.sqlite")

    /// Exposed so the menu can reveal the file in Finder. The README promises
    /// this is a plain file you can delete, which is only true if you can find it.
    public nonisolated let url: URL

    private let handle: Handle
    private var db: OpaquePointer { handle.pointer }

    /// SQLite's own name for "copy this string, I will outlive your buffer".
    /// It is a macro, so the Swift importer drops it and it has to be spelled by
    /// hand. Binding a Swift `String` with the default `SQLITE_STATIC` instead
    /// hands SQLite a buffer that dies at the end of the statement, which writes
    /// silent garbage rather than failing.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let schemaVersion: Int32 = 1

    public init(url: URL) throws {
        self.url = url
        // Wrapped rather than rethrown: the app renders these by name, and a raw
        // NSCocoaErrorDomain code reaches the menu as unreadable noise.
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw MistakeStoreError.couldNotOpen(error.localizedDescription)
        }
        var handle: OpaquePointer?
        // FULLMUTEX because an actor serialises calls but does not pin a thread:
        // successive statements land on whichever cooperative-pool thread is
        // free. A handle opened NOMUTEX would corrupt only under load, which is
        // the worst kind of bug to go looking for later.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(url.path)"
            sqlite3_close(handle)
            throw MistakeStoreError.couldNotOpen(message)
        }
        self.handle = Handle(pointer: handle)
        // WAL because the app is not the only thing that opens this file: the
        // README tells you to inspect it with the sqlite3 shell, and the default
        // journal mode makes that a lock fight.
        try Self.exec(handle, "PRAGMA journal_mode = WAL;")
        try Self.exec(handle, "PRAGMA busy_timeout = 2000;")
        try Self.migrate(handle)
    }

    // MARK: - Schema

    private static func migrate(_ db: OpaquePointer) throws {
        guard try userVersion(db) < schemaVersion else { return }
        try exec(db, "BEGIN;")
        try exec(db, """
            CREATE TABLE IF NOT EXISTS mistakes (
              id        INTEGER PRIMARY KEY,
              at        INTEGER NOT NULL,
              category  TEXT    NOT NULL,
              severity  TEXT    NOT NULL,
              original  TEXT    NOT NULL,
              corrected TEXT    NOT NULL,
              why_l1    TEXT    NOT NULL,
              app       TEXT,
              exported  INTEGER NOT NULL DEFAULT 0
            );
            """)
        try exec(db, "CREATE INDEX IF NOT EXISTS mistakes_at ON mistakes(at);")
        // One row per day, not per sentence. A correct sentence has to leave a
        // trace the digest can count without the log keeping what was written.
        //
        // Both numbers live here rather than one here and one counted out of
        // `mistakes`, because this table is day granular and `mistakes` is second
        // granular. Reading the ratio from two different resolutions is how a
        // review ends up claiming fifteen mistakes in twelve sentences.
        try exec(db, """
            CREATE TABLE IF NOT EXISTS checks (
              day          TEXT    PRIMARY KEY,
              total        INTEGER NOT NULL,
              with_mistake INTEGER NOT NULL DEFAULT 0
            );
            """)
        try exec(db, "PRAGMA user_version = \(schemaVersion);")
        try exec(db, "COMMIT;")
    }

    private static func userVersion(_ db: OpaquePointer) throws -> Int32 {
        let statement = try prepare(db, "PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(statement, 0)
    }

    // MARK: - Writing

    /// Records one check. Every verdict lands here, including the correct ones
    /// and the categories the popup filter mutes, because `VerdictFilter` decides
    /// what interrupts the writer and nothing else.
    public func record(_ verdict: Verdict, original: String, app: String?, at: Date) throws {
        try countCheck(on: at, wasMistake: verdict.outcome == .error)
        guard verdict.outcome == .error else { return }

        let statement = try Self.prepare(db, """
            INSERT INTO mistakes (at, category, severity, original, corrected, why_l1, app)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(at.timeIntervalSince1970))
        Self.bind(statement, 2, verdict.category.rawValue)
        Self.bind(statement, 3, verdict.severity.rawValue)
        Self.bind(statement, 4, original)
        Self.bind(statement, 5, verdict.corrected)
        Self.bind(statement, 6, verdict.whyL1)
        if let app { Self.bind(statement, 7, app) } else { sqlite3_bind_null(statement, 7) }
        try Self.step(db, statement)
    }

    private func countCheck(on date: Date, wasMistake: Bool) throws {
        let mistake = wasMistake ? 1 : 0
        let statement = try Self.prepare(db, """
            INSERT INTO checks (day, total, with_mistake) VALUES (?, 1, ?)
            ON CONFLICT(day) DO UPDATE SET
              total = total + 1, with_mistake = with_mistake + ?;
            """)
        defer { sqlite3_finalize(statement) }
        Self.bind(statement, 1, Self.day(date))
        sqlite3_bind_int(statement, 2, Int32(mistake))
        sqlite3_bind_int(statement, 3, Int32(mistake))
        try Self.step(db, statement)
    }

    public func markExported(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        let holes = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let statement = try Self.prepare(db, "UPDATE mistakes SET exported = 1 WHERE id IN (\(holes));")
        defer { sqlite3_finalize(statement) }
        for (offset, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(offset + 1), id)
        }
        try Self.step(db, statement)
    }

    /// Empties the log in place rather than unlinking the file, so the store the
    /// app is already holding stays usable. Deleting the file underneath an open
    /// handle leaves the next write talking to an inode nobody can find.
    public func deleteEverything() throws {
        try Self.exec(db, "DELETE FROM mistakes;")
        try Self.exec(db, "DELETE FROM checks;")
        try Self.exec(db, "VACUUM;")
    }

    // MARK: - Reading

    /// Newest first, which is the order the review reads best in and the order
    /// `MistakeDigest` expects when it breaks a tie on recency.
    public func mistakes(since: Date, now: Date) throws -> [Mistake] {
        let statement = try Self.prepare(db, """
            SELECT id, at, category, severity, original, corrected, why_l1, app, exported
            FROM mistakes WHERE at >= ? AND at <= ? ORDER BY at DESC, id DESC;
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(now.timeIntervalSince1970))

        var result: [Mistake] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let category = Category(rawValue: Self.text(statement, 2)),
                  let severity = Severity(rawValue: Self.text(statement, 3))
            else { continue }  // A category from a newer build. Skip it, do not fail the review.
            result.append(
                Mistake(
                    id: sqlite3_column_int64(statement, 0),
                    at: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1))),
                    category: category,
                    severity: severity,
                    original: Self.text(statement, 4),
                    corrected: Self.text(statement, 5),
                    whyL1: Self.text(statement, 6),
                    app: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Self.text(statement, 7),
                    exported: sqlite3_column_int(statement, 8) != 0
                )
            )
        }
        return result
    }

    /// Everything the review window needs, in one hop across the actor.
    public func review(
        since: Date, now: Date, limits: MistakeDigest.Limits = .default
    ) throws -> MistakeDigest {
        MistakeDigest.build(
            from: try mistakes(since: since, now: now),
            counts: try counts(since: since, now: now),
            limits: limits
        )
    }

    /// Both halves of the review header, read together so they always describe
    /// the same span of days.
    ///
    /// Day granularity, because that is all `checks` keeps. The review window is
    /// a week, so a whole-day boundary is the right resolution and the only one
    /// that costs nothing in stored text.
    public func counts(since: Date, now: Date) throws -> CheckCounts {
        let statement = try Self.prepare(db, """
            SELECT COALESCE(SUM(total), 0), COALESCE(SUM(with_mistake), 0)
            FROM checks WHERE day >= ? AND day <= ?;
            """)
        defer { sqlite3_finalize(statement) }
        Self.bind(statement, 1, Self.day(since))
        Self.bind(statement, 2, Self.day(now))
        guard sqlite3_step(statement) == SQLITE_ROW else { return CheckCounts(checked: 0, withMistake: 0) }
        return CheckCounts(
            checked: Int(sqlite3_column_int64(statement, 0)),
            withMistake: Int(sqlite3_column_int64(statement, 1))
        )
    }

    // MARK: - SQLite plumbing

    /// UTC, and sortable as a string, which is what lets the window be a plain
    /// `BETWEEN` on the primary key instead of a date function.
    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw MistakeStoreError.couldNotWrite(message)
        }
    }

    private static func prepare(_ db: OpaquePointer?, _ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MistakeStoreError.couldNotPrepare(message(db))
        }
        return statement
    }

    private static func step(_ db: OpaquePointer?, _ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MistakeStoreError.couldNotWrite(message(db))
        }
    }

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: raw)
    }

    private static func message(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }
}
