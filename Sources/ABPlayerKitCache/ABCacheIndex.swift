import Foundation

/// Validator captured from the response that actually supplied the bytes
/// currently on disk for an entry (not from a HEAD) — see
/// `ABCacheStore.prepareFill`. Used to send `If-Range` on resume and
/// `If-None-Match`/`If-Modified-Since` on session-start revalidation.
struct ABCacheValidator: Codable, Sendable, Equatable {
    var etag: String?
    var lastModified: String?

    /// RFC 9110 forbids weak comparison in range requests — a weak `ETag`
    /// is stored (revalidation's `If-None-Match` may use it) but never sent
    /// as `If-Range`.
    var isStrongETag: Bool { etag.map { !$0.hasPrefix("W/") } ?? false }
}

struct ABCacheIndex: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let key: String
        let fileName: String
        var size: Int64
        var contentLength: Int64?
        var contentType: String?
        var isComplete: Bool
        var lastAccessedAt: Date
        var validator: ABCacheValidator?

        init(
            key: String,
            fileName: String? = nil,
            size: Int64,
            contentLength: Int64? = nil,
            contentType: String? = nil,
            isComplete: Bool = false,
            lastAccessedAt: Date,
            validator: ABCacheValidator? = nil
        ) {
            self.key = key
            self.fileName = fileName ?? "\(key).data"
            self.size = size
            self.contentLength = contentLength
            self.contentType = contentType
            self.isComplete = isComplete
            self.lastAccessedAt = lastAccessedAt
            self.validator = validator
        }
    }

    private(set) var entries: [String: Entry]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    var totalSize: Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    mutating func upsert(_ entry: Entry) {
        entries[entry.key] = entry
    }

    @discardableResult
    mutating func remove(key: String) -> Entry? {
        entries.removeValue(forKey: key)
    }

    mutating func touch(key: String, at date: Date) {
        entries[key]?.lastAccessedAt = date
    }

    mutating func evictLRU(
        to maximumSize: Int64,
        excluding excludedKeys: Set<String> = []
    ) -> [Entry] {
        let targetSize = Swift.max(0, maximumSize)
        guard totalSize > targetSize else { return [] }

        let oldestFirst = entries.values.sorted {
            if $0.lastAccessedAt == $1.lastAccessedAt {
                return $0.key < $1.key
            }
            return $0.lastAccessedAt < $1.lastAccessedAt
        }
        var evicted: [Entry] = []
        var remainingSize = totalSize
        for entry in oldestFirst where remainingSize > targetSize && !excludedKeys.contains(entry.key) {
            entries[entry.key] = nil
            remainingSize -= entry.size
            evicted.append(entry)
        }
        return evicted
    }
}
