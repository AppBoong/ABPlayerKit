import Foundation

struct ABByteRange: Sendable, Equatable {
    let lowerBound: Int64
    let upperBound: Int64?

    init(lowerBound: Int64, upperBound: Int64?) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    static func parse(_ header: String) -> ABByteRange? {
        let parts = header.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "bytes"
        else { return nil }

        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(",") else { return nil }
        let bounds = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let lowerBound = Int64(bounds[0].trimmingCharacters(in: .whitespaces)),
              lowerBound >= 0
        else { return nil }

        let upperString = bounds[1].trimmingCharacters(in: .whitespaces)
        if upperString.isEmpty {
            return ABByteRange(lowerBound: lowerBound, upperBound: nil)
        }
        guard let upperBound = Int64(upperString), upperBound >= lowerBound else { return nil }
        return ABByteRange(lowerBound: lowerBound, upperBound: upperBound)
    }

    static func merge(_ ranges: [ABByteRange]) -> [ABByteRange] {
        let sortedRanges = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return ($0.upperBound ?? .max) < ($1.upperBound ?? .max)
            }
            return $0.lowerBound < $1.lowerBound
        }
        guard var current = sortedRanges.first else { return [] }

        var merged: [ABByteRange] = []
        for range in sortedRanges.dropFirst() {
            guard let currentUpperBound = current.upperBound else { continue }
            let touchesCurrent = range.lowerBound <= currentUpperBound
                || (currentUpperBound < .max && range.lowerBound == currentUpperBound + 1)
            if touchesCurrent {
                let upperBound: Int64?
                if range.upperBound == nil {
                    upperBound = nil
                } else {
                    upperBound = Swift.max(currentUpperBound, range.upperBound!)
                }
                current = ABByteRange(lowerBound: current.lowerBound, upperBound: upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}
