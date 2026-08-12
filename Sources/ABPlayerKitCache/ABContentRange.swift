import Foundation

/// A parsed `Content-Range` response header (`bytes <start>-<end>/<total>`).
/// `start`/`end` are nil for the `bytes */<total>` form; `total` is nil for
/// the `bytes <start>-<end>/*` form (total unknown).
struct ABContentRange: Sendable, Equatable {
    let start: Int64?
    let end: Int64?
    let total: Int64?

    static func parse(_ header: String) -> ABContentRange? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let rest = trimmed.dropFirst("bytes ".count)
        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let rangePart = parts[0].trimmingCharacters(in: .whitespaces)
        let totalPart = parts[1].trimmingCharacters(in: .whitespaces)
        let total: Int64? = totalPart == "*" ? nil : Int64(totalPart)
        guard totalPart == "*" || total != nil else { return nil }

        if rangePart == "*" {
            guard let total else { return nil }
            return ABContentRange(start: nil, end: nil, total: total)
        }

        let bounds = rangePart.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let start = Int64(bounds[0].trimmingCharacters(in: .whitespaces)),
              let end = Int64(bounds[1].trimmingCharacters(in: .whitespaces)),
              start >= 0, end >= start
        else { return nil }
        return ABContentRange(start: start, end: end, total: total)
    }
}
