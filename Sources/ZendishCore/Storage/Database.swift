import Foundation
import SQLite3

public struct DatabaseError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

enum SQLValue {
    case text(String?)
    case real(Double)
    case integer(Int)
}

/// A small wrapper around SQLite. Every value is bound as a parameter, never joined into SQL.
/// It isn't thread-safe on its own, so it must only be used from `RecipeStore`.
final class Database {
    private let handle: OpaquePointer
    // Tells SQLite to keep its own copy of bound text.
    private static let copyText = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(opened)
            throw DatabaseError(description: "Couldn't open the database: \(message)")
        }
        handle = opened
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        try query(sql, values) { _ in }
    }

    @discardableResult
    func query<Result>(_ sql: String, _ values: [SQLValue] = [], row read: (Row) -> Result) throws -> [Result] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text?): status = sqlite3_bind_text(statement, index, text, -1, Self.copyText)
            case .text(nil): status = sqlite3_bind_null(statement, index)
            case .real(let number): status = sqlite3_bind_double(statement, index, number)
            case .integer(let number): status = sqlite3_bind_int64(statement, index, Int64(number))
            }
            guard status == SQLITE_OK else { throw lastError() }
        }

        var results: [Result] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: results.append(read(Row(statement: statement)))
            case SQLITE_DONE: return results
            default: throw lastError()
            }
        }
    }

    /// Runs `work` as one unit, so a failure part-way leaves the database unchanged.
    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func lastError() -> DatabaseError {
        DatabaseError(description: String(cString: sqlite3_errmsg(handle)))
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func real(_ column: Int32) -> Double {
            sqlite3_column_double(statement, column)
        }

        func integer(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }
    }
}
