import ABPlayerKit
@preconcurrency import Foundation
import UniformTypeIdentifiers

struct ABCachedResource: Sendable {
    let data: Data
    let contentLength: Int64
    let contentType: String
}

actor ABCacheStore {
    private struct RemoteMetadata: Sendable {
        let contentLength: Int64?
        let contentType: String
    }

    private enum StoreError: Error {
        case invalidResponse
        case entryTooLarge
    }

    private let configuration: ABCacheConfiguration
    private let fileManager: FileManager
    private let dataDirectory: URL
    private let indexURL: URL
    private var index: ABCacheIndex
    private var fills: [String: Task<Void, Error>] = [:]

    init(configuration: ABCacheConfiguration, fileManager: FileManager = .default) throws {
        self.configuration = configuration
        self.fileManager = fileManager
        self.dataDirectory = configuration.directory.appendingPathComponent("Progressive", isDirectory: true)
        self.indexURL = configuration.directory.appendingPathComponent("progressive-index.json")

        try fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var loadedIndex: ABCacheIndex
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(ABCacheIndex.self, from: data) {
            loadedIndex = decoded
        } else {
            loadedIndex = ABCacheIndex()
        }
        for entry in loadedIndex.entries.values {
            let url = dataDirectory.appendingPathComponent(entry.fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                loadedIndex.remove(key: entry.key)
                continue
            }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            var reconciledEntry = entry
            reconciledEntry.size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            reconciledEntry.isComplete = reconciledEntry.contentLength.map {
                reconciledEntry.size >= $0
            } ?? false
            loadedIndex.upsert(reconciledEntry)
        }
        self.index = loadedIndex
        let indexData = try JSONEncoder().encode(loadedIndex)
        try indexData.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: indexURL.path
        )
    }

    func totalSize() -> Int64 {
        index.totalSize
    }

    func remove(_ source: ABMediaSource) throws {
        let key = ABCacheKey.derive(from: source)
        fills[key]?.cancel()
        fills[key] = nil
        if let entry = index.remove(key: key) {
            try? fileManager.removeItem(at: fileURL(for: entry))
            try persistIndex()
        }
    }

    func removeAll() throws {
        for task in fills.values {
            task.cancel()
        }
        fills.removeAll()
        if fileManager.fileExists(atPath: dataDirectory.path) {
            try fileManager.removeItem(at: dataDirectory)
        }
        try fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        index = ABCacheIndex()
        try persistIndex()
    }

    func load(_ source: ABMediaSource, range: ABByteRange) async throws -> ABCachedResource {
        let key = ABCacheKey.derive(from: source)
        if let entry = index.entries[key], entry.isComplete,
           fileManager.fileExists(atPath: fileURL(for: entry).path) {
            index.touch(key: key, at: Date())
            try persistIndex()
            return try resource(from: entry, range: range)
        }

        let metadata = try await remoteMetadata(for: source)
        if let contentLength = metadata.contentLength,
           contentLength > cacheableEntryLimit {
            try? remove(source)
            return try await passthrough(
                source,
                range: range,
                metadata: metadata
            )
        }

        do {
            try await ensureSequentialFill(
                source,
                key: key,
                metadata: metadata
            )
        } catch StoreError.entryTooLarge {
            try? remove(source)
            return try await passthrough(
                source,
                range: range,
                metadata: metadata
            )
        }

        guard let entry = index.entries[key] else { throw StoreError.invalidResponse }
        index.touch(key: key, at: Date())
        try persistIndex()
        return try resource(from: entry, range: range)
    }

    private func ensureSequentialFill(
        _ source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata
    ) async throws {
        if let fill = fills[key] {
            try await fill.value
            return
        }

        let fill = Task {
            try await performSequentialFill(source, key: key, metadata: metadata)
        }
        fills[key] = fill
        do {
            try await fill.value
            fills[key] = nil
        } catch {
            fills[key] = nil
            throw error
        }
    }

    private func performSequentialFill(
        _ source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata
    ) async throws {
        var entry = index.entries[key] ?? ABCacheIndex.Entry(
            key: key,
            size: 0,
            contentLength: metadata.contentLength,
            contentType: metadata.contentType,
            lastAccessedAt: Date()
        )
        let destinationURL = fileURL(for: entry)
        if !fileManager.fileExists(atPath: destinationURL.path) {
            fileManager.createFile(
                atPath: destinationURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            entry.size = 0
        } else {
            entry.size = fileSize(at: destinationURL)
        }

        var request = URLRequest(url: source.url)
        for (field, value) in source.httpHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if entry.size > 0 {
            request.setValue("bytes=\(entry.size)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else { throw StoreError.invalidResponse }

        if httpResponse.statusCode == 200, entry.size > 0 {
            try Data().write(to: destinationURL, options: .atomic)
            entry.size = 0
        }
        if let totalLength = Self.totalLength(from: httpResponse) {
            entry.contentLength = totalLength
        }
        entry.contentType = Self.contentType(from: httpResponse, fallback: metadata.contentType)

        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var buffer = Data()
        buffer.reserveCapacity(64 * 1_024)
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1_024 {
                try handle.write(contentsOf: buffer)
                entry.size += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                try updatePartialEntry(entry)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            entry.size += Int64(buffer.count)
            try updatePartialEntry(entry)
        }

        entry.isComplete = entry.contentLength.map { entry.size >= $0 } ?? (httpResponse.statusCode == 200)
        entry.lastAccessedAt = Date()
        index.upsert(entry)
        try evictIfNeeded(protecting: key)
        try persistIndex()
    }

    private func updatePartialEntry(_ entry: ABCacheIndex.Entry) throws {
        guard entry.size <= cacheableEntryLimit else {
            throw StoreError.entryTooLarge
        }
        var partialEntry = entry
        partialEntry.lastAccessedAt = Date()
        index.upsert(partialEntry)
        try persistIndex()
    }

    private func passthrough(
        _ source: ABMediaSource,
        range: ABByteRange,
        metadata: RemoteMetadata
    ) async throws -> ABCachedResource {
        var request = URLRequest(url: source.url)
        for (field, value) in source.httpHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue(range.headerValue, forHTTPHeaderField: "Range")

        let (receivedData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else { throw StoreError.invalidResponse }

        let data: Data
        if httpResponse.statusCode == 200,
           let resolvedRange = range.resolved(
               contentLength: metadata.contentLength ?? Int64(receivedData.count)
           ) {
            let lowerBound = Swift.min(Int64(receivedData.count), resolvedRange.lowerBound)
            let upperBound = resolvedRange.upperBound.map { Swift.min(Int64(receivedData.count) - 1, $0) }
                ?? Int64(receivedData.count) - 1
            if lowerBound <= upperBound {
                data = receivedData.subdata(in: Int(lowerBound)..<Int(upperBound + 1))
            } else {
                data = Data()
            }
        } else {
            data = receivedData
        }

        return ABCachedResource(
            data: data,
            contentLength: metadata.contentLength ?? Self.totalLength(from: httpResponse) ?? Int64(data.count),
            contentType: Self.contentType(from: httpResponse, fallback: metadata.contentType)
        )
    }

    private func remoteMetadata(for source: ABMediaSource) async throws -> RemoteMetadata {
        var request = URLRequest(url: source.url)
        request.httpMethod = "HEAD"
        for (field, value) in source.httpHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let (_, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) {
            return RemoteMetadata(
                contentLength: Self.totalLength(from: httpResponse),
                contentType: Self.contentType(from: httpResponse, fallback: UTType.mpeg4Movie.identifier)
            )
        }

        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else { throw StoreError.invalidResponse }
        return RemoteMetadata(
            contentLength: Self.totalLength(from: httpResponse),
            contentType: Self.contentType(from: httpResponse, fallback: UTType.mpeg4Movie.identifier)
        )
    }

    private func resource(from entry: ABCacheIndex.Entry, range: ABByteRange) throws -> ABCachedResource {
        let contentLength = entry.contentLength ?? entry.size
        guard let range = range.resolved(contentLength: contentLength),
              contentLength > 0,
              range.lowerBound < contentLength
        else {
            return ABCachedResource(
                data: Data(),
                contentLength: contentLength,
                contentType: entry.contentType ?? UTType.mpeg4Movie.identifier
            )
        }

        let requestedUpperBound = range.upperBound ?? (contentLength - 1)
        let upperBound = Swift.min(requestedUpperBound, entry.size - 1)
        guard upperBound >= range.lowerBound else {
            return ABCachedResource(
                data: Data(),
                contentLength: contentLength,
                contentType: entry.contentType ?? UTType.mpeg4Movie.identifier
            )
        }

        let handle = try FileHandle(forReadingFrom: fileURL(for: entry))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let count = Int(upperBound - range.lowerBound + 1)
        let data = try handle.read(upToCount: count) ?? Data()
        return ABCachedResource(
            data: data,
            contentLength: contentLength,
            contentType: entry.contentType ?? UTType.mpeg4Movie.identifier
        )
    }

    private func evictIfNeeded(protecting protectedKey: String) throws {
        let protectedEntry = index.remove(key: protectedKey)
        let evicted = index.evictLRU(to: configuration.maximumDiskSize - (protectedEntry?.size ?? 0))
        if let protectedEntry {
            index.upsert(protectedEntry)
        }
        for entry in evicted {
            try? fileManager.removeItem(at: fileURL(for: entry))
        }
    }

    private func persistIndex() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: indexURL.path
        )
    }

    private func fileURL(for entry: ABCacheIndex.Entry) -> URL {
        dataDirectory.appendingPathComponent(entry.fileName)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private var cacheableEntryLimit: Int64 {
        Swift.max(0, Swift.min(configuration.maximumEntrySize, configuration.maximumDiskSize))
    }

    private static func totalLength(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let value = Int64(total) {
            return value
        }
        return response.expectedContentLength >= 0 ? response.expectedContentLength : nil
    }

    private static func contentType(from response: HTTPURLResponse, fallback: String) -> String {
        guard let mimeType = response.mimeType,
              let type = UTType(mimeType: mimeType)
        else { return fallback }
        return type.identifier
    }
}
