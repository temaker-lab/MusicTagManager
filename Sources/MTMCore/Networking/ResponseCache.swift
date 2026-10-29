import Foundation
import GRDB

/// 외부 API 응답 캐시 (api_cache 테이블). 같은 앨범·곡은 다시 요청하지 않는다.
public final class ResponseCache: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func get(_ key: String, maxAge: TimeInterval) throws -> Data? {
        try database.writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT response_json, fetched_at FROM api_cache WHERE key = ?", arguments: [key])
            guard let row, let fetched: Date = row["fetched_at"], Date().timeIntervalSince(fetched) <= maxAge,
                  let text: String = row["response_json"] else { return nil }
            return Data(text.utf8)
        }
    }

    public func put(_ key: String, provider: String, data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { return }
        try database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO api_cache (key, provider, response_json, fetched_at) VALUES (?, ?, ?, ?)",
                           arguments: [key, provider, text, Date()])
        }
    }
}
