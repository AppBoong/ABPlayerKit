@preconcurrency import Foundation

struct ABHTTPResponse: Sendable, Equatable {
    let statusCode: Int
    let expectedContentLength: Int64?
    let mimeType: String?
    let headers: [String: String]

    init(
        statusCode: Int,
        expectedContentLength: Int64?,
        mimeType: String?,
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.expectedContentLength = expectedContentLength
        self.mimeType = mimeType
        self.headers = headers.reduce(into: [:]) {
            $0[$1.key.lowercased()] = $1.value
        }
    }

    init(_ response: HTTPURLResponse) {
        self.init(
            statusCode: response.statusCode,
            expectedContentLength: response.expectedContentLength >= 0
                ? response.expectedContentLength
                : nil,
            mimeType: response.mimeType,
            headers: response.allHeaderFields.reduce(into: [:]) { headers, pair in
                guard let field = pair.key as? String else { return }
                headers[field] = String(describing: pair.value)
            }
        )
    }

    func value(forHTTPHeaderField field: String) -> String? {
        headers[field.lowercased()]
    }
}

enum ABHTTPFetchEvent: Sendable, Equatable {
    case response(ABHTTPResponse)
    case data(Data)
}

protocol ABHTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse)
    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error>
}

// URLSession instances are immutable after initialization and delegate state is lock-protected.
final class ABURLSessionHTTPFetcher: ABHTTPFetching, @unchecked Sendable {
    private let streamDelegate: ABHTTPStreamDelegate
    private let streamSession: URLSession
    private let dataSession: URLSession

    init() {
        let streamDelegate = ABHTTPStreamDelegate()
        self.streamDelegate = streamDelegate
        self.streamSession = URLSession(
            configuration: .ephemeral,
            delegate: streamDelegate,
            delegateQueue: nil
        )
        self.dataSession = URLSession(configuration: .ephemeral)
    }

    deinit {
        streamSession.invalidateAndCancel()
        dataSession.invalidateAndCancel()
    }

    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse) {
        let (data, response) = try await dataSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, ABHTTPResponse(response))
    }

    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error> {
        AsyncThrowingStream { [streamDelegate, streamSession] continuation in
            let task = streamSession.dataTask(with: request)
            streamDelegate.register(continuation, for: task.taskIdentifier)
            continuation.onTermination = { [streamDelegate, weak task] _ in
                streamDelegate.unregister(taskIdentifier: task?.taskIdentifier)
                task?.cancel()
            }
            task.resume()
        }
    }
}

// URLSession may call concurrently; all continuation storage is protected by the lock.
private final class ABHTTPStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<ABHTTPFetchEvent, any Error>.Continuation

    private let lock = NSLock()
    private var continuations: [Int: Continuation] = [:]

    func register(_ continuation: Continuation, for taskIdentifier: Int) {
        lock.lock()
        continuations[taskIdentifier] = continuation
        lock.unlock()
    }

    func unregister(taskIdentifier: Int?) {
        guard let taskIdentifier else { return }
        lock.lock()
        continuations[taskIdentifier] = nil
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              let continuation = continuation(for: dataTask.taskIdentifier)
        else {
            completionHandler(.cancel)
            return
        }
        continuation.yield(.response(ABHTTPResponse(response)))
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        continuation(for: dataTask.taskIdentifier)?.yield(.data(data))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }

    private func continuation(for taskIdentifier: Int) -> Continuation? {
        lock.lock()
        let continuation = continuations[taskIdentifier]
        lock.unlock()
        return continuation
    }
}
