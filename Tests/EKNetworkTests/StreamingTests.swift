//
//  StreamingTests.swift
//  EKNetworkTests
//
//  Created by Emil Karimov on 09.05.2026.
//  Copyright © 2026 Emil Karimov. All rights reserved.
//
//  Tests for the streaming API introduced in 1.6.0:
//  `URLSessionStreamingProtocol`, `StreamingResponse`, and `NetworkManager.stream(_:accessToken:)`.
//

import Testing
import Foundation
@testable import EKNetwork

// MARK: - Test fixtures

/// Mock streaming session that yields pre-defined byte chunks and returns a synthetic
/// `HTTPURLResponse`. Captures the issued `URLRequest` so tests can assert on headers/URL.
private final class MockStreamingSession: URLSessionStreamingProtocol, @unchecked Sendable {

    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
        let error: Error?
    }

    private let response: Response
    private(set) var lastRequest: URLRequest?

    init(response: Response) {
        self.response = response
    }

    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        self.lastRequest = request
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        let chunks = response.chunks
        let error = response.error
        let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                for chunk in chunks {
                    for byte in chunk {
                        continuation.yield(byte)
                    }
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
        return (stream, httpResponse)
    }
}

private struct StreamRequest: NetworkRequest {
    typealias Response = EmptyResponse
    var path: String { "/api/v1/stream" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { ["X-Device-ID": "device-123", "X-Custom": "yes"] }
}

private struct StreamItem: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

// MARK: - Tests

@Suite("Streaming")
struct StreamingTests {

    @Test("stream() reuses NetworkManager pipeline: applies headers and Authorization")
    func appliesPipelineHeaders() async throws {
        let mock = MockStreamingSession(response: .init(
            statusCode: 200,
            headers: ["Content-Type": "application/x-ndjson"],
            chunks: [Data("{\"id\":1,\"name\":\"a\"}\n".utf8)],
            error: nil
        ))

        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        let stream = try await manager.stream(StreamRequest(), accessToken: { "secret-token" })
        // Drain so the request completes deterministically.
        for try await _ in stream.bytes {}

        let req = try #require(mock.lastRequest)
        #expect(req.value(forHTTPHeaderField: "X-Device-ID") == "device-123")
        #expect(req.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(req.url?.absoluteString == "https://unit.test/api/v1/stream")
    }

    @Test("stream() throws invalidResponse when the head is not HTTP")
    func nonHTTPResponseThrowsInvalidResponse() async throws {
        final class NonHTTPSession: URLSessionStreamingProtocol, @unchecked Sendable {
            func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
                let response = URLResponse(
                    url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
                )
                let empty = AsyncThrowingStream<UInt8, Error> { $0.finish() }
                return (empty, response)
            }
        }
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: NonHTTPSession()
        )
        await #expect(throws: StreamingError.invalidResponse) {
            _ = try await manager.stream(StreamRequest(), accessToken: nil)
        }
    }

    @Test("ndjson() decodes one JSON object per line")
    func decodesNDJSON() async throws {
        let payload = """
        {"id":1,"name":"first"}
        {"id":2,"name":"second"}
        {"id":3,"name":"third"}

        """ // trailing newline + empty line — должен корректно отработать
        let mock = MockStreamingSession(response: .init(
            statusCode: 200,
            headers: [:],
            // Split intentionally in the middle of a line to verify buffering across chunks.
            chunks: [
                Data(payload.prefix(20).utf8),
                Data(payload.dropFirst(20).utf8)
            ],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        let response = try await manager.stream(StreamRequest(), accessToken: nil)
        var collected: [StreamItem] = []
        for try await item in response.ndjson(as: StreamItem.self) {
            collected.append(item)
        }

        #expect(collected == [
            StreamItem(id: 1, name: "first"),
            StreamItem(id: 2, name: "second"),
            StreamItem(id: 3, name: "third")
        ])
    }

    @Test("lines() handles CRLF line endings and skips blank lines")
    func crlfAndBlankLines() async throws {
        let payload = "alpha\r\n\r\nbeta\r\ngamma"
        let mock = MockStreamingSession(response: .init(
            statusCode: 200,
            headers: [:],
            chunks: [Data(payload.utf8)],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )
        let response = try await manager.stream(StreamRequest(), accessToken: nil)
        var lines: [String] = []
        for try await line in response.lines() { lines.append(line) }
        #expect(lines == ["alpha", "beta", "gamma"])
    }

    @Test("non-2xx response throws HTTPError with payload")
    func nonSuccessThrowsHTTPError() async throws {
        let mock = MockStreamingSession(response: .init(
            statusCode: 500,
            headers: [:],
            chunks: [Data("{\"error\":\"boom\"}".utf8)],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        do {
            _ = try await manager.stream(StreamRequest(), accessToken: nil)
            Issue.record("Expected HTTPError to be thrown")
        } catch let error as HTTPError {
            #expect(error.statusCode == 500)
            #expect(String(data: error.data, encoding: .utf8) == "{\"error\":\"boom\"}")
        }
    }

    @Test("401 triggers token refresh and retries once when allowsRetry is true")
    func retriesOn401WithTokenRefresh() async throws {
        // Two-stage mock: first request returns 401, second returns 200.
        // Implemented via a final class that flips state after the first call.
        final class StagedSession: URLSessionStreamingProtocol, @unchecked Sendable {
            var calls = 0
            func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
                calls += 1
                let isFirst = calls == 1
                let url = request.url!
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: isFirst ? 401 : 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                let body = isFirst ? Data() : Data("{\"id\":1,\"name\":\"ok\"}\n".utf8)
                let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self) { continuation in
                    for byte in body { continuation.yield(byte) }
                    continuation.finish()
                }
                return (stream, response)
            }
        }

        final class Refresher: TokenRefreshProvider, @unchecked Sendable {
            var refreshes = 0
            func refreshTokenIfNeeded() async throws { refreshes += 1 }
        }

        let session = StagedSession()
        let refresher = Refresher()
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        manager.tokenRefresher = refresher

        let response = try await manager.stream(StreamRequest(), accessToken: { "stale" })
        var items: [StreamItem] = []
        for try await item in response.ndjson(as: StreamItem.self) { items.append(item) }

        #expect(session.calls == 2)
        #expect(refresher.refreshes == 1)
        #expect(items == [StreamItem(id: 1, name: "ok")])
    }

    @Test("401 with allowsRetry=false throws NetworkError.unauthorized without refresh")
    func noRetryWhenAllowsRetryFalse() async throws {
        struct NoRetryRequest: NetworkRequest {
            typealias Response = EmptyResponse
            var path: String { "/no-retry" }
            var method: HTTPMethod { .get }
            var allowsRetry: Bool { false }
        }

        let mock = MockStreamingSession(response: .init(
            statusCode: 401,
            headers: [:],
            chunks: [Data()],
            error: nil
        ))
        final class Refresher: TokenRefreshProvider, @unchecked Sendable {
            var refreshes = 0
            func refreshTokenIfNeeded() async throws { refreshes += 1 }
        }
        let refresher = Refresher()
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )
        manager.tokenRefresher = refresher

        do {
            _ = try await manager.stream(NoRetryRequest(), accessToken: nil)
            Issue.record("Expected NetworkError.unauthorized")
        } catch NetworkError.unauthorized {
            #expect(refresher.refreshes == 0)
        }
    }

    @Test("custom errorDecoder is invoked on non-2xx response")
    func customErrorDecoder() async throws {
        struct ServerError: Error, Equatable {
            let code: String
        }
        struct DecoderRequest: NetworkRequest {
            typealias Response = EmptyResponse
            var path: String { "/decode" }
            var method: HTTPMethod { .get }
            var errorDecoder: ((Data) -> Error?)? {
                { _ in ServerError(code: "BUSINESS_RULE") }
            }
        }
        let mock = MockStreamingSession(response: .init(
            statusCode: 422,
            headers: [:],
            chunks: [Data("{\"code\":\"BUSINESS_RULE\"}".utf8)],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        do {
            _ = try await manager.stream(DecoderRequest(), accessToken: nil)
            Issue.record("Expected ServerError")
        } catch let error as ServerError {
            #expect(error.code == "BUSINESS_RULE")
        }
    }

    @Test("401 with allowsRetry=false and errorDecoder throws the custom error")
    func customErrorDecoderOn401WithoutRetry() async throws {
        // Reaches the `statusCode == 401` branch in performStream where refresh-retry is NOT
        // allowed (allowsRetry == false) and an errorDecoder is provided → the custom error is
        // thrown instead of NetworkError.unauthorized (Streaming.swift line 307).
        struct ServerError: Error, Equatable { let code: String }
        struct NoRetryDecoderRequest: NetworkRequest {
            typealias Response = EmptyResponse
            var path: String { "/decode-401" }
            var method: HTTPMethod { .get }
            var allowsRetry: Bool { false }
            var errorDecoder: ((Data) -> Error?)? {
                { _ in ServerError(code: "TOKEN_EXPIRED") }
            }
        }
        let mock = MockStreamingSession(response: .init(
            statusCode: 401,
            headers: [:],
            chunks: [Data("{\"code\":\"TOKEN_EXPIRED\"}".utf8)],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        do {
            _ = try await manager.stream(NoRetryDecoderRequest(), accessToken: nil)
            Issue.record("Expected ServerError from custom decoder on 401")
        } catch let error as ServerError {
            #expect(error.code == "TOKEN_EXPIRED")
        }
    }

    @Test("non-2xx error payload larger than 1 MiB throws errorPayloadTooLarge")
    func errorPayloadTooLargeOnNonSuccess() async throws {
        // The drain() helper caps the buffered error payload at maxErrorPayloadBytes (1 MiB).
        // A non-2xx response whose body exceeds the cap must throw StreamingError
        // .errorPayloadTooLarge (Streaming.swift line 348). The payload is built lazily inside
        // the mock so we don't materialise > 1 MiB of Data up front needlessly — but a single
        // Data over the limit is sufficient and simplest.
        let limit = 1 * 1024 * 1024
        let oversized = Data(repeating: 0x41, count: limit + 16) // 1 MiB + 16 bytes
        let mock = MockStreamingSession(response: .init(
            statusCode: 500,
            headers: [:],
            chunks: [oversized],
            error: nil
        ))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: mock
        )

        await #expect(throws: StreamingError.errorPayloadTooLarge(limitBytes: limit)) {
            _ = try await manager.stream(StreamRequest(), accessToken: nil)
        }
    }

    @Test("byteStream/lines/ndjson propagate a mid-stream error")
    func midStreamErrorPropagates() async throws {
        struct MidStreamError: Error {}

        func makeManager() -> NetworkManager {
            let mock = MockStreamingSession(response: .init(
                statusCode: 200,
                headers: [:],
                // Several valid NDJSON lines, then the stream fails mid-flight.
                chunks: [Data("{\"id\":1,\"name\":\"a\"}\n{\"id\":2,\"name\":\"b\"}\n".utf8)],
                error: MidStreamError()
            ))
            return NetworkManager(
                baseURL: URL(string: "https://unit.test")!,
                streamingSession: mock
            )
        }

        // Raw bytes stream surfaces the error (Streaming.swift byteStream bridge / consumer).
        do {
            let response = try await makeManager().stream(StreamRequest(), accessToken: nil)
            for try await _ in response.bytes {}
            Issue.record("Expected raw bytes iteration to throw")
        } catch is MidStreamError {
            // expected
        }

        // lines() forwards the error from its bridging task (Streaming.swift line 173).
        do {
            let response = try await makeManager().stream(StreamRequest(), accessToken: nil)
            var seen: [String] = []
            for try await line in response.lines() { seen.append(line) }
            Issue.record("Expected lines() iteration to throw")
        } catch is MidStreamError {
            // expected
        }

        // ndjson() forwards the error from its bridging task (Streaming.swift line 209).
        do {
            let response = try await makeManager().stream(StreamRequest(), accessToken: nil)
            var items: [StreamItem] = []
            for try await item in response.ndjson(as: StreamItem.self) { items.append(item) }
            Issue.record("Expected ndjson() iteration to throw")
        } catch is MidStreamError {
            // expected
        }
    }

    @Test("URLSession default conformance is wired without explicit streamingSession")
    func defaultURLSessionStreamingConformance() async throws {
        // Verifies that constructing NetworkManager without a streamingSession parameter is
        // source-compatible AND ends up with a working streaming session (URLSession.shared
        // satisfies URLSessionStreamingProtocol). We don't actually hit the network here —
        // the assertion is purely structural.
        let manager = NetworkManager(baseURL: URL(string: "https://unit.test")!)
        #expect(manager.streamingSession is URLSession)
    }

    // MARK: - Fix B regression: no extra 401 round-trip when tokenRefresher == nil

    /// Counting streaming session that records how many times `byteStream` is invoked and
    /// always returns the same HTTP status with the given body.
    private final class CountingStreamingSession: URLSessionStreamingProtocol, @unchecked Sendable {
        let statusCode: Int
        let body: Data
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.withLock { _calls } }

        init(statusCode: Int, body: Data = Data()) {
            self.statusCode = statusCode
            self.body = body
        }

        func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
            lock.withLock { _calls += 1 }
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = self.body
            let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self) { continuation in
                for byte in body { continuation.yield(byte) }
                continuation.finish()
            }
            return (stream, response)
        }
    }

    @Test("Fix B: stream() 401 with tokenRefresher == nil makes exactly one call and throws unauthorized")
    func stream401NoRefresherSingleCall() async throws {
        let session = CountingStreamingSession(statusCode: 401)
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        // tokenRefresher intentionally left nil.
        do {
            _ = try await manager.stream(StreamRequest(), accessToken: { "stale" })
            Issue.record("Expected NetworkError.unauthorized")
        } catch NetworkError.unauthorized {
            // Expected: no refresh path, immediate unauthorized.
        }
        #expect(session.calls == 1, "Without a tokenRefresher the 401 must NOT trigger a second round-trip")
    }

    @Test("Fix B: stream() 401 with tokenRefresher == nil and errorDecoder throws custom error, one call")
    func stream401NoRefresherCustomError() async throws {
        struct ServerError: Error, Equatable { let code: String }
        struct DecoderRequest: NetworkRequest {
            typealias Response = EmptyResponse
            var path: String { "/decode-401" }
            var method: HTTPMethod { .get }
            var errorDecoder: ((Data) -> Error?)? { { _ in ServerError(code: "EXPIRED") } }
        }
        let session = CountingStreamingSession(statusCode: 401, body: Data("{\"code\":\"EXPIRED\"}".utf8))
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        // tokenRefresher intentionally left nil.
        do {
            _ = try await manager.stream(DecoderRequest(), accessToken: { "stale" })
            Issue.record("Expected custom ServerError")
        } catch let error as ServerError {
            #expect(error == ServerError(code: "EXPIRED"))
        }
        #expect(session.calls == 1, "errorDecoder path must still issue exactly one round-trip when refresher is nil")
    }

    @Test("Fix B regression: stream() 401 with refresher does exactly one refresh + one retry")
    func stream401WithRefresherSingleRefreshSingleRetry() async throws {
        final class StagedSession: URLSessionStreamingProtocol, @unchecked Sendable {
            private let lock = NSLock()
            private var _calls = 0
            var calls: Int { lock.withLock { _calls } }
            func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
                let isFirst = lock.withLock { _calls += 1; return _calls == 1 }
                let url = request.url!
                let response = HTTPURLResponse(url: url, statusCode: isFirst ? 401 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                let body = isFirst ? Data() : Data("{\"id\":7,\"name\":\"ok\"}\n".utf8)
                let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self) { continuation in
                    for byte in body { continuation.yield(byte) }
                    continuation.finish()
                }
                return (stream, response)
            }
        }
        final class Refresher: TokenRefreshProvider, @unchecked Sendable {
            var refreshes = 0
            func refreshTokenIfNeeded() async throws { refreshes += 1 }
        }

        let session = StagedSession()
        let refresher = Refresher()
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        manager.tokenRefresher = refresher

        let response = try await manager.stream(StreamRequest(), accessToken: { "stale" })
        var items: [StreamItem] = []
        for try await item in response.ndjson(as: StreamItem.self) { items.append(item) }

        #expect(session.calls == 2, "Exactly one refresh + one retry — no double round-trip")
        #expect(refresher.refreshes == 1, "Refresh must happen exactly once (no double refresh)")
        #expect(items == [StreamItem(id: 7, name: "ok")])
    }
}

// MARK: - Real URLSession.byteStream bridging

/// `URLProtocol` stub that delivers a synthetic response head, then either streams a fixed
/// body to EOF or fails mid-stream. Lets the real `URLSession.byteStream(for:)` bridging task
/// run end-to-end without hitting the network.
private final class ByteStreamStubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func makeByteStreamStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ByteStreamStubProtocol.self]
    return URLSession(configuration: config)
}

/// `URLProtocol` stub that delivers a 200 head, emits some body bytes, then fails the load with a
/// `URLProtocol` stub that delivers a 200 head, then streams body chunks slowly over time and
/// never reaches EOF until cancelled. Lets the consumer break out of iteration mid-stream so the
/// real `URLSession.byteStream(for:)` bridging task hits its `catch` branch via the cooperative
/// cancellation check (`Task.checkCancellation()` → `continuation.finish(throwing:)`,
/// Streaming.swift lines 70/75).
private final class ByteStreamSlowProtocol: URLProtocol {
    nonisolated(unsafe) static var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { Self.cancelled = true }

    override func startLoading() {
        Self.cancelled = false
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Drip a byte at a time on a background queue so the head is delivered up front and the
        // consumer has time to cancel mid-stream.
        let queue = DispatchQueue(label: "bytestream.slow")
        func emit() {
            queue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
                guard let self, Self.cancelled == false else { return }
                self.client?.urlProtocol(self, didLoad: Data([0x41]))
                emit()
            }
        }
        emit()
    }
}

private func makeByteStreamSlowSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ByteStreamSlowProtocol.self]
    return URLSession(configuration: config)
}

@Suite("URLSession.byteStream default conformance")
struct URLSessionByteStreamTests {

    @Test("byteStream yields every body byte and finishes on EOF")
    func byteStreamHappyPath() async throws {
        ByteStreamStubProtocol.body = Data("hello".utf8)
        let session = makeByteStreamStubSession()

        let (stream, response) = try await session.byteStream(
            for: URLRequest(url: URL(string: "https://stub.test/x")!)
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        var received: [UInt8] = []
        for try await byte in stream { received.append(byte) }
        #expect(received == Array("hello".utf8))
    }

    @Test("byteStream bridging task finishes (throwing) when iteration is cancelled mid-stream")
    func byteStreamCancelledMidStream() async throws {
        let session = makeByteStreamSlowSession()

        let (stream, response) = try await session.byteStream(
            for: URLRequest(url: URL(string: "https://stub.test/slow")!)
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        // Consume a few bytes, then break — this triggers `onTermination`, cancelling the bridging
        // task. The in-flight `for try await byte` then throws from `Task.checkCancellation()`,
        // routing through the bridge's catch (Streaming.swift line 75). Breaking out of the loop
        // here exercises that termination path without the test itself throwing.
        var received = 0
        for try await _ in stream {
            received += 1
            if received >= 3 { break }
        }
        #expect(received == 3)
    }
}
