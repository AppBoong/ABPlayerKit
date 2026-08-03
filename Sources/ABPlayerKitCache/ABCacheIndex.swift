import Foundation

struct ABCacheIndex: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let key: String
        let fileName: String
        var size: Int64
        var contentLength: Int64?
        var contentType: String?
        var isComplete: Bool
        var lastAccessedAt: Date

        init(
            key: String,
            fileName: String? = nil,
            size: Int64,
            contentLength: Int64? = nil,
            contentType: String? = nil,
            isComplete: Bool = false,
            lastAccessedAt: Date
        ) {
            self.key = key
            self.fileName = fileName ?? "\(key).data"
            self.size = size
            self.contentLength = contentLength
            self.contentType = contentType
            self.isComplete = isComplete
            self.lastAccessedAt = lastAccessedAt
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

    mutating func evictLRU(to maximumSize: Int64) -> [Entry] {
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
        for entry in oldestFirst where remainingSize > targetSize {
            entries[entry.key] = nil
            remainingSize -= entry.size
            evicted.append(entry)
        }
        return evicted
    }
}
