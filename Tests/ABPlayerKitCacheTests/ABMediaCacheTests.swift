import ABPlayerKit
import ABPlayerKitCache
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKitCache

private final class ABFakeHLSDownloadSession: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [UUID: @Sendable (ABHLSDownloadResult) -> Void] = [:]
    private(set) var cancellationCount = 0
    private(set) var invalidationCount = 0

    func start(
        id: UUID,
        source: ABMediaSource,
        bitrate: Double?,
        completion: @escaping @Sendable (ABHLSDownloadResult) -> Void
    ) -> (@Sendable () -> Void)? {
        lock.lock()
        completions[id] = completion
        lock.unlock()
        return { [weak self] in
            self?.cancel(id: id)
        }
    }

    func completeFirst(at url: URL) {
        lock.lock()
        guard let entry = completions.first else {
            lock.unlock()
            return
        }
        completions[entry.key] = nil
        lock.unlock()
        entry.value(.success(url))
    }

    func invalidate() {
        lock.lock()
        invalidationCount += 1
        let completions = Array(self.completions.values)
        self.completions.removeAll()
        lock.unlock()
        for completion in completions {
            completion(.failure)
        }
    }

    private func cancel(id: UUID) {
        lock.lock()
        if completions.removeValue(forKey: id) != nil {
            cancellationCount += 1
        }
        lock.unlock()
    }
}

@Suite("ABMediaCache asset interception")
struct ABMediaCacheTests {
    @Test("Asset factory intercepts progressive sources and passes HLS through")
    func interceptsOnlyProgressiveSources() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ABMediaCache(configuration: .init(directory: directory))
        let factory = cache.makeAssetFactory()
        let progressive = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)
        let hls = ABMediaSource(url: URL(string: "https://example.com/master.m3u8")!)

        #expect(factory.makeAsset(for: progressive).url.scheme == "ab-cache")
        #expect(factory.makeAsset(for: hls).url == hls.url)
    }

    @Test("A new cache is empty and removal APIs remain idempotent")
    func emptyCacheOperations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ABMediaCache(configuration: .init(directory: directory))
        let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)

        #expect(await cache.totalSize() == 0)
        await cache.remove(source)
        await cache.removeAll()
        #expect(await cache.totalSize() == 0)
    }
}

@Suite("ABHLSPrefetcher bookkeeping")
struct ABHLSPrefetcherTests {
    @Test("Handle cancellation removes and cancels its fake download")
    func handleCancellation() {
        let fakeSession = ABFakeHLSDownloadSession()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefetcher = ABHLSPrefetcher(configuration: .init(directory: directory)) {
            fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
        }
        let source = ABMediaSource(url: URL(string: "https://example.com/master.m3u8")!)

        let handle = prefetcher.prefetch(source, minimumRequiredMediaBitrate: 1_000_000)
        #expect(prefetcher.activeTaskCount == 1)
        handle.cancel()

        #expect(prefetcher.activeTaskCount == 0)
        #expect(fakeSession.cancellationCount == 1)
    }

    @Test("Completed downloads become local assets and can be removed")
    func completionAndRemoval() async throws {
        let fakeSession = ABFakeHLSDownloadSession()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localURL = directory.appendingPathComponent("asset.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        let prefetcher = ABHLSPrefetcher(configuration: .init(directory: directory)) {
            fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
        }
        let source = ABMediaSource(url: URL(string: "https://example.com/master.m3u8")!)

        prefetcher.prefetch(source)
        fakeSession.completeFirst(at: localURL)

        #expect(prefetcher.localAsset(for: source)?.url == localURL)
        await prefetcher.remove(source)
        #expect(prefetcher.localAsset(for: source) == nil)
        #expect(!FileManager.default.fileExists(atPath: localURL.path))
    }

    @Test("cancelAll cancels every active fake download")
    func cancelAll() {
        let fakeSession = ABFakeHLSDownloadSession()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefetcher = ABHLSPrefetcher(configuration: .init(directory: directory)) {
            fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
        }

        prefetcher.prefetch(ABMediaSource(url: URL(string: "https://example.com/a.m3u8")!))
        prefetcher.prefetch(ABMediaSource(url: URL(string: "https://example.com/b.m3u8")!))
        prefetcher.cancelAll()

        #expect(prefetcher.activeTaskCount == 0)
        #expect(fakeSession.cancellationCount == 2)
    }

    @Test("Invalidation cancels active work and invalidates the download session")
    func invalidatesSession() {
        let fakeSession = ABFakeHLSDownloadSession()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefetcher = ABHLSPrefetcher(
            configuration: .init(directory: directory),
            startDownload: {
                fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
            },
            invalidateDownload: {
                fakeSession.invalidate()
            }
        )
        prefetcher.prefetch(ABMediaSource(url: URL(string: "https://example.com/a.m3u8")!))

        prefetcher.invalidate()

        #expect(prefetcher.activeTaskCount == 0)
        #expect(fakeSession.cancellationCount == 1)
        #expect(fakeSession.invalidationCount == 1)
    }

    @Test("Shared session invalidation completes other prefetchers' jobs")
    func invalidationCompletesSharedJobs() {
        let fakeSession = ABFakeHLSDownloadSession()
        let firstDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let startDownload: ABHLSDownloadStart = {
            fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
        }
        let first = ABHLSPrefetcher(
            configuration: .init(directory: firstDirectory),
            startDownload: startDownload,
            invalidateDownload: { fakeSession.invalidate() }
        )
        let second = ABHLSPrefetcher(
            configuration: .init(directory: secondDirectory),
            startDownload: startDownload,
            invalidateDownload: { fakeSession.invalidate() }
        )
        first.prefetch(ABMediaSource(url: URL(string: "https://example.com/a.m3u8")!))
        second.prefetch(ABMediaSource(url: URL(string: "https://example.com/b.m3u8")!))

        first.invalidate()

        #expect(first.activeTaskCount == 0)
        #expect(second.activeTaskCount == 0)
        #expect(fakeSession.invalidationCount == 1)
    }

    @Test("Persisted HLS locations are home-relative and survive reconstruction")
    func persistsHomeRelativeLocations() throws {
        let fakeSession = ABFakeHLSDownloadSession()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localURL = directory.appendingPathComponent("asset.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        let configuration = ABCacheConfiguration(directory: directory)
        let source = ABMediaSource(url: URL(string: "https://example.com/master.m3u8")!)
        let prefetcher = ABHLSPrefetcher(configuration: configuration) {
            fakeSession.start(id: $0, source: $1, bitrate: $2, completion: $3)
        }
        prefetcher.prefetch(source)
        fakeSession.completeFirst(at: localURL)

        let data = try Data(contentsOf: directory.appendingPathComponent("hls-index.json"))
        let paths = try JSONDecoder().decode([String: String].self, from: data)
        #expect(paths.values.allSatisfy { !$0.hasPrefix("/") })

        let restored = ABHLSPrefetcher(configuration: configuration) { _, _, _, _ in nil }
        #expect(restored.localAsset(for: source)?.url == localURL)
    }

    @Test("Background downloads use the stable package identifier")
    func stableBackgroundIdentifier() {
        #expect(ABHLSBackgroundSession.identifier == "ABPlayerKitCache.HLS")
    }
}
