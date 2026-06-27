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

    @Test("URLSession default conformance is wired without explicit streamingSession")
    func defaultURLSessionStreamingConformance() async throws {
        // Verifies that constructing NetworkManager without a streamingSession parameter is
        // source-compatible AND ends up with a working streaming session (URLSession.shared
        // satisfies URLSessionStreamingProtocol). We don't actually hit the network here —
        // the assertion is purely structural.
        let manager = NetworkManager(baseURL: URL(string: "https://unit.test")!)
        #expect(manager.streamingSession is URLSession)
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
}
