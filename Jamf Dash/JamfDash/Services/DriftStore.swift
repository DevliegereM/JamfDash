import Foundation
import SQLite3
import OSLog

// MARK: - DriftStore

final class DriftStore: @unchecked Sendable {

    // MARK: Properties

    static let shared = DriftStore()

    private static let logger = Logger(subsystem: "com.jamfdash", category: "DriftStore")

    private let dbURL: URL
    private let dbQueue: DispatchSerialQueue

    // MARK: Initialization

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JamfDash", isDirectory: true)

        dbURL = appSupport.appendingPathComponent("drift.db")
        dbQueue = DispatchSerialQueue(label: "com.jamfdash.DriftStore")

        dbQueue.sync {
            self.openAndMigrate()
        }
    }

    // MARK: - Private helpers

    private func openAndMigrate() {
        guard ensureDirectory() else { return }

        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else {
            Self.logger.error("Failed to open drift.db at \(self.dbURL.path)")
            return
        }
        defer { sqlite3_close(db) }

        let migrations = """
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS snapshots (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            taken_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS snapshot_items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id INTEGER NOT NULL,
            item_type   TEXT NOT NULL,
            item_id     TEXT NOT NULL,
            item_name   TEXT NOT NULL,
            item_category TEXT
        );
        CREATE TABLE IF NOT EXISTS drift_events (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            detected_at TEXT NOT NULL,
            item_type   TEXT NOT NULL,
            item_id     TEXT NOT NULL,
            item_name   TEXT NOT NULL,
            change_type TEXT NOT NULL,
            old_value   TEXT,
            new_value   TEXT
        );
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, migrations, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            Self.logger.error("Migration failed: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    private func ensureDirectory() -> Bool {
        let dir = dbURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create JamfDash directory: \(error)")
                return false
            }
        }
        return true
    }

    @discardableResult
    private func withDB<T>(_ block: (OpaquePointer) -> T) -> T? {
        var result: T?
        dbQueue.sync {
            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else {
                Self.logger.error("Failed to open drift.db for read/write")
                return
            }
            defer { sqlite3_close(db) }
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            result = block(db)
        }
        return result
    }

    // MARK: - Public API

    func fetchLatestSnapshotItems(for type: DriftItemType) -> [SnapshotItemRow] {
        withDB { db in
            var rows: [SnapshotItemRow] = []

            let sql = """
            SELECT si.item_id, si.item_name, si.item_category
            FROM snapshot_items si
            INNER JOIN (
                SELECT MAX(id) AS max_id FROM snapshots
            ) latest ON si.snapshot_id = latest.max_id
            WHERE si.item_type = ?
            ORDER BY si.item_name ASC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return rows
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (type.rawValue as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let itemId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let category = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                rows.append(SnapshotItemRow(itemId: itemId, name: name, category: category))
            }
            return rows
        } ?? []
    }

    func insertSnapshot(takenAt: String) -> Int64 {
        withDB { db in
            let sql = "INSERT INTO snapshots (taken_at) VALUES (?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return Int64(0)
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (takenAt as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            return sqlite3_last_insert_rowid(db)
        } ?? 0
    }

    func insertSnapshotItems(_ items: [SnapshotItemRow], type: DriftItemType, snapshotId: Int64) {
        guard !items.isEmpty else { return }
        withDB { db in
            let sql = """
            INSERT INTO snapshot_items (snapshot_id, item_type, item_id, item_name, item_category)
            VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for item in items {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, snapshotId)
                sqlite3_bind_text(stmt, 2, (type.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (item.itemId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (item.name as NSString).utf8String, -1, nil)
                if let cat = item.category {
                    sqlite3_bind_text(stmt, 5, (cat as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                sqlite3_step(stmt)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    func insertDriftEvents(_ events: [DriftEvent]) {
        guard !events.isEmpty else { return }
        withDB { db in
            let sql = """
            INSERT INTO drift_events (detected_at, item_type, item_id, item_name, change_type, old_value, new_value)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }

            let iso = ISO8601DateFormatter()
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for event in events {
                sqlite3_reset(stmt)
                let dateStr = iso.string(from: event.detectedAt)
                sqlite3_bind_text(stmt, 1, (dateStr as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (event.itemType.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (event.itemId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (event.itemName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (event.changeType.rawValue as NSString).utf8String, -1, nil)
                if let old = event.oldValue {
                    sqlite3_bind_text(stmt, 6, (old as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                if let new = event.newValue {
                    sqlite3_bind_text(stmt, 7, (new as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                sqlite3_step(stmt)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    func fetchAllDriftEvents() -> [DriftEvent] {
        withDB { db in
            var events: [DriftEvent] = []
            let sql = """
            SELECT id, detected_at, item_type, item_id, item_name, change_type, old_value, new_value
            FROM drift_events
            ORDER BY id DESC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return events
            }
            defer { sqlite3_finalize(stmt) }

            let iso = ISO8601DateFormatter()
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let dateStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let detectedAt = iso.date(from: dateStr) ?? Date()
                let itemTypeRaw = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let itemId = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let itemName = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                let changeTypeRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                let oldValue = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                let newValue = sqlite3_column_text(stmt, 7).map { String(cString: $0) }

                guard let itemType = DriftItemType(rawValue: itemTypeRaw),
                      let changeType = DriftChangeType(rawValue: changeTypeRaw) else { continue }

                events.append(DriftEvent(
                    id: id,
                    detectedAt: detectedAt,
                    itemType: itemType,
                    itemId: itemId,
                    itemName: itemName,
                    changeType: changeType,
                    oldValue: oldValue,
                    newValue: newValue
                ))
            }
            return events
        } ?? []
    }

    func pruneSnapshots(keepLast: Int = 50) {
        withDB { db in
            let sql = """
            DELETE FROM snapshots
            WHERE id NOT IN (
                SELECT id FROM snapshots ORDER BY id DESC LIMIT ?
            );
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(keepLast))
            sqlite3_step(stmt)

            // Also prune orphaned snapshot items
            sqlite3_exec(db, """
            DELETE FROM snapshot_items
            WHERE snapshot_id NOT IN (SELECT id FROM snapshots);
            """, nil, nil, nil)
        }
    }

    var snapshotCount: Int {
        withDB { db in
            let sql = "SELECT COUNT(*) FROM snapshots;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        } ?? 0
    }
}
