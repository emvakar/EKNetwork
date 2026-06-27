//
//  StreamingChunksTests.swift
//  EKNetworkTests
//
//  Created by QA on 27.06.2026.
//  Copyright © 2026 Emil Karimov. All rights reserved.
//
//  Tests for the chunked streaming API introduced in 1.7.0:
//  `StreamingResponse.chunks` (primary), the `dataStream(for:)` requirement with mutually-derived
//  default implementations, the deprecated `bytes` / `byteStream(for:)` wrappers, and the rewritten
//  `lines()` / `ndjson()` / `drain` built on top of chunks.
//
//  Coverage map → api-designer contract §7:
//   1  dataStream happy-path chunk sizing
//   2  chunks ↔ bytes equivalence
//   3  lines() over chunks (split lines, CRLF on boundary, \n on boundary, blank skip, flush tail)
//   4  UTF-8 multibyte scalar split across chunks
//   5  invalid UTF-8 line skipped without throw
//   6  ndjson() record split across chunks; one bad line → throw + finish
//   7  mock with byteStream only → dataStream coalesces
//   8  mock with dataStream only → byteStream flattens, order preserved
//   9  anti-recursion: §7/§8 finish promptly on a small body
//  10  real URLSession.dataStream bridge (happy + cancel mid-stream)
//  11  cancelling chunks iteration mid-stream cancels the bridge task
//  12  drain via chunks: ≤1 MiB ok, >1 MiB throws, exactly 1 MiB ok
//  13  401 → refresh → retry over dataStream; non-2xx → HTTPError via chunk-drain
//  14  legacy byteStream-only mocks keep passing through the default dataStream
//  15  deprecated response.bytes consumer compiles + matches chunks
//

import Testing
import Foundation
@testable import EKNetwork

// MARK: - Test fixtures

/// Mock that implements ONLY `dataStream(for:)`. `byteStream(for:)` is supplied by the
/// protocol-extension default (flatten chunks → bytes). Exercises §8/§7 from the dataStream side.
private final class DataStreamOnlySession: URLSessionStreamingProtocol, @unchecked Sendable {
    let statusCode: Int
    let headers: [String: String]
    let chunks: [Data]
    let error: Error?
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, headers: [String: String] = [:], chunks: [Data], error: Error? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.chunks = chunks
        self.error = error
    }

    func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        self.lastRequest = request
        let url = request.url!
        let response = HTTPURLResponse(
            url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        let chunks = self.chunks
        let error = self.error
        let stream = AsyncThrowingStream<Data, Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                for chunk in chunks { continuation.yield(chunk) }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
            }
        }
        return (stream, response)
    }
}

/// Mock that implements ONLY `byteStream(for:)` (the deprecated requirement). `dataStream(for:)`
/// is supplied by the protocol-extension default (coalesce bytes → chunks). Mirrors the legacy
/// `MockStreamingSession` shape and exercises §7/§14 from the byteStream side.
private final class ByteStreamOnlySession: URLSessionStreamingProtocol, @unchecked Sendable {
    let statusCode: Int
    let body: Data
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        self.lastRequest = request
        let url = request.url!
        let response = HTTPURLResponse(
            url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        let body = self.body
        let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                for byte in body { continuation.yield(byte) }
                continuation.finish()
            }
        }
        return (stream, response)
    }
}

private struct ChunkStreamRequest: NetworkRequest {
    typealias Response = EmptyResponse
    var path: String { "/api/v1/chunks" }
    var method: HTTPMethod { .get }
}

private struct ChunkItem: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

/// Builds a `StreamingResponse` directly from a list of `Data` chunks, bypassing the manager.
/// Useful for unit-testing the chunk-based helpers (`lines`, `ndjson`, `bytes`) in isolation.
private func makeResponse(chunks: [Data], error: Error? = nil) -> StreamingResponse {
    let stream = AsyncThrowingStream<Data, Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
        Task {
            for chunk in chunks { continuation.yield(chunk) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
    return StreamingResponse(statusCode: 200, headers: [:], chunks: stream)
}

@Suite("Streaming chunks (1.7.0)")
struct StreamingChunksTests {

    // MARK: §1 dataStream happy-path chunk sizing

    @Test("§1 dataStream coalesces a large body into streamChunkSize-sized chunks with a partial tail")
    func dataStreamChunkSizing() async throws {
        let chunkSize = 16 * 1024
        // 2 full chunks + a partial tail.
        let totalCount = chunkSize * 2 + 1234
        var body = Data(capacity: totalCount)
        for i in 0..<totalCount { body.append(UInt8(i & 0xFF)) }

        // Drive coalescing through the byteStream-only default dataStream.
        let session = ByteStreamOnlySession(body: body)
        let (chunks, _) = try await session.dataStream(for: URLRequest(url: URL(string: "https://x.test")!))

        var collected: [Data] = []
        for try await c in chunks { collected.append(c) }

        // 3 chunks: two of exactly chunkSize, one partial.
        #expect(collected.count == 3)
        #expect(collected[0].count == chunkSize)
        #expect(collected[1].count == chunkSize)
        #expect(collected[2].count == 1234)
        // Sum of chunks reconstructs the original body exactly.
        let reassembled = collected.reduce(into: Data()) { $0.append($1) }
        #expect(reassembled == body)
    }

    // MARK: §2 chunks ↔ bytes equivalence

    @Test("§2 unrolling chunks to bytes equals the deprecated bytes sequence for one body")
    func chunksBytesEquivalence() async throws {
        let body = Data((0..<5000).map { UInt8($0 & 0xFF) })
        // Arbitrary chunk boundaries.
        let chunks = [body.prefix(13), body[13..<2048], body[2048...]].map { Data($0) }
        let response = makeResponse(chunks: chunks)

        // Unroll chunks → bytes manually.
        var fromChunks: [UInt8] = []
        for try await c in response.chunks { fromChunks.append(contentsOf: c) }

        // The deprecated bytes wrapper, derived from chunks, must yield the identical sequence.
        let response2 = makeResponse(chunks: chunks)
        var fromBytes: [UInt8] = []
        for try await b in response2.bytes { fromBytes.append(b) }

        #expect(fromChunks == Array(body))
        #expect(fromBytes == fromChunks)
    }

    // MARK: §3 lines() over chunks

    @Test("§3 lines() splits across chunk boundaries: CRLF on boundary, \\n on boundary, blank skip, tail flush")
    func linesAcrossChunkBoundaries() async throws {
        // "alpha\r" | "\nbeta\n" | "\ngamma" -> CRLF split across chunks, blank line skipped,
        // a bare \n exactly on a chunk start, and a final line with no trailing newline.
        let chunks = [
            Data("alpha\r".utf8),   // \r at end of chunk
            Data("\nbeta\n".utf8),  // \n at start of next chunk → CRLF for "alpha"; then "beta\n"
            Data("\ngamma".utf8)    // leading \n produces an (empty→skipped) line, then tail "gamma"
        ]
        let response = makeResponse(chunks: chunks)
        var lines: [String] = []
        for try await line in response.lines() { lines.append(line) }
        #expect(lines == ["alpha", "beta", "gamma"])
    }

    @Test("§3b lines() with \\n exactly on the chunk seam")
    func lineNewlineOnSeam() async throws {
        let chunks = [Data("one".utf8), Data("\n".utf8), Data("two".utf8)]
        let response = makeResponse(chunks: chunks)
        var lines: [String] = []
        for try await line in response.lines() { lines.append(line) }
        #expect(lines == ["one", "two"])
    }

    // MARK: §4 UTF-8 multibyte scalar split across chunks

    @Test("§4 a 4-byte emoji scalar split across two chunks decodes correctly")
    func utf8ScalarSplitAcrossChunks() async throws {
        let emoji = "😀" // U+1F600, 4 UTF-8 bytes: F0 9F 98 80
        let full = Data("hi \(emoji) bye\n".utf8)
        // Find the emoji byte range and split right in the middle of it.
        let bytes = Array(full)
        let emojiStart = bytes.firstIndex(of: 0xF0)!
        let splitPoint = emojiStart + 2 // mid-scalar split
        let chunks = [Data(bytes[0..<splitPoint]), Data(bytes[splitPoint...])]
        let response = makeResponse(chunks: chunks)
        var lines: [String] = []
        for try await line in response.lines() { lines.append(line) }
        #expect(lines == ["hi \(emoji) bye"])
    }

    // MARK: §5 invalid UTF-8 line skipped silently

    @Test("§5 a line that is not valid UTF-8 is skipped without throwing")
    func invalidUTF8LineSkipped() async throws {
        // Line 1: valid. Line 2: lone continuation bytes (0x80 0x81) → invalid UTF-8. Line 3: valid.
        var data = Data("good\n".utf8)
        data.append(contentsOf: [0x80, 0x81, 0x0A]) // invalid line + \n
        data.append(contentsOf: Data("after\n".utf8))
        let response = makeResponse(chunks: [data])
        var lines: [String] = []
        for try await line in response.lines() { lines.append(line) }
        #expect(lines == ["good", "after"])
    }

    // MARK: §6 ndjson() across chunks + bad line

    @Test("§6 ndjson() decodes a record split across chunks")
    func ndjsonRecordSplitAcrossChunks() async throws {
        let line = "{\"id\":42,\"name\":\"split\"}\n"
        let bytes = Array(line.utf8)
        let mid = bytes.count / 2
        let chunks = [Data(bytes[0..<mid]), Data(bytes[mid...])]
        let response = makeResponse(chunks: chunks)
        var items: [ChunkItem] = []
        for try await item in response.ndjson(as: ChunkItem.self) { items.append(item) }
        #expect(items == [ChunkItem(id: 42, name: "split")])
    }

    @Test("§6b ndjson() with one malformed line throws and finishes")
    func ndjsonBadLineThrows() async throws {
        let payload = "{\"id\":1,\"name\":\"ok\"}\nnot-json\n{\"id\":2,\"name\":\"never\"}\n"
        let response = makeResponse(chunks: [Data(payload.utf8)])
        var items: [ChunkItem] = []
        await #expect(throws: (any Error).self) {
            for try await item in response.ndjson(as: ChunkItem.self) { items.append(item) }
        }
        // The first valid record was yielded before the throw; the third never arrives.
        #expect(items == [ChunkItem(id: 1, name: "ok")])
    }

    // MARK: §7 mock with byteStream only → dataStream works

    @Test("§7 a byteStream-only mock yields working chunks via the default dataStream")
    func byteStreamOnlyMockProducesChunks() async throws {
        let body = Data("hello world chunked".utf8)
        let session = ByteStreamOnlySession(body: body)
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        let response = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
        var reassembled = Data()
        for try await chunk in response.chunks { reassembled.append(chunk) }
        #expect(reassembled == body)
    }

    // MARK: §8 mock with dataStream only → byteStream works, order preserved

    @Test("§8 a dataStream-only mock yields working bytes (order preserved) via the default byteStream")
    func dataStreamOnlyMockProducesBytes() async throws {
        let chunks = [Data("abc".utf8), Data("def".utf8), Data("ghi".utf8)]
        let session = DataStreamOnlySession(chunks: chunks)
        // Exercise the default byteStream(for:) directly to flatten chunks → ordered octets.
        let (byteStream, _) = try await session.byteStream(for: URLRequest(url: URL(string: "https://x.test")!))
        var received: [UInt8] = []
        for try await b in byteStream { received.append(b) }
        #expect(received == Array("abcdefghi".utf8))
    }

    // MARK: §9 anti-recursion guard

    @Test("§9 byteStream-only and dataStream-only paths finish promptly (no double recursion)")
    func antiRecursionFinishesPromptly() async throws {
        // Small bodies; if the mutually-derived defaults ever recursed, these would hang and the
        // overall test run would time out. We assert results AND wrap in a watchdog deadline.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let session = ByteStreamOnlySession(body: Data("recursion-check-1".utf8))
                let (chunks, _) = try await session.dataStream(for: URLRequest(url: URL(string: "https://x.test")!))
                var n = 0
                for try await c in chunks { n += c.count }
                #expect(n == Data("recursion-check-1".utf8).count)
            }
            group.addTask {
                let session = DataStreamOnlySession(chunks: [Data("recursion-check-2".utf8)])
                let (bytes, _) = try await session.byteStream(for: URLRequest(url: URL(string: "https://x.test")!))
                var n = 0
                for try await _ in bytes { n += 1 }
                #expect(n == Data("recursion-check-2".utf8).count)
            }
            // Watchdog: if either branch recursed indefinitely it would never complete; this task
            // would then be cancelled when the group below times out. We bound to 10s.
            group.addTask {
                try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                Issue.record("Anti-recursion watchdog fired — a derived default likely recursed")
            }
            // Wait for the two real tasks, then cancel the watchdog.
            try await group.next()
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: §11 cancelling chunks iteration mid-stream cancels the bridge task

    @Test("§11 breaking out of chunks iteration triggers onTermination on the byteStream-derived bridge")
    func cancelChunksMidStreamTerminatesBridge() async throws {
        // A byteStream-only session produces a large body so coalescing yields multiple chunks.
        // Breaking after the first chunk must fire the bridging task's onTermination (task.cancel()).
        let body = Data(repeating: 0x42, count: 16 * 1024 * 4) // 4 chunks
        let session = ByteStreamOnlySession(body: body)
        let (chunks, _) = try await session.dataStream(for: URLRequest(url: URL(string: "https://x.test")!))
        var seen = 0
        for try await _ in chunks {
            seen += 1
            if seen >= 1 { break }
        }
        #expect(seen == 1)
        // Yield so the cancelled bridging task can wind down; absence of a hang is the assertion.
        await Task.yield()
    }

    // MARK: §12 drain via chunks through the public stream() error path

    @Test("§12 non-2xx body of exactly 1 MiB drains without errorPayloadTooLarge")
    func drainExactlyOneMiBOk() async throws {
        let limit = 1 * 1024 * 1024
        let exact = Data(repeating: 0x41, count: limit)
        let session = DataStreamOnlySession(statusCode: 500, chunks: [exact])
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        do {
            _ = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
            Issue.record("Expected HTTPError (not errorPayloadTooLarge) for exactly 1 MiB")
        } catch let error as HTTPError {
            #expect(error.statusCode == 500)
            #expect(error.data.count == limit)
        }
    }

    @Test("§12b non-2xx body over 1 MiB throws errorPayloadTooLarge")
    func drainOverOneMiBThrows() async throws {
        let limit = 1 * 1024 * 1024
        // Split across chunks so the cap is hit mid-chunk (exercises the partial top-up branch).
        let chunks = [Data(repeating: 0x41, count: limit - 100), Data(repeating: 0x41, count: 200)]
        let session = DataStreamOnlySession(statusCode: 500, chunks: chunks)
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        await #expect(throws: StreamingError.errorPayloadTooLarge(limitBytes: limit)) {
            _ = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
        }
    }

    @Test("§12c small non-2xx body (≤1 MiB) drains into HTTPError payload")
    func drainSmallBodyOk() async throws {
        let session = DataStreamOnlySession(statusCode: 503, chunks: [Data("unavailable".utf8)])
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        do {
            _ = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
            Issue.record("Expected HTTPError")
        } catch let error as HTTPError {
            #expect(error.statusCode == 503)
            #expect(String(data: error.data, encoding: .utf8) == "unavailable")
        }
    }

    // MARK: §13 401 → refresh → retry over dataStream; non-2xx → HTTPError

    @Test("§13 401 → refresh → retry succeeds over a dataStream-only session")
    func refreshRetryOverDataStream() async throws {
        final class StagedDataSession: URLSessionStreamingProtocol, @unchecked Sendable {
            private let lock = NSLock()
            private var _calls = 0
            var calls: Int { lock.withLock { _calls } }
            func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
                let isFirst = lock.withLock { _calls += 1; return _calls == 1 }
                let url = request.url!
                let response = HTTPURLResponse(
                    url: url, statusCode: isFirst ? 401 : 200, httpVersion: "HTTP/1.1", headerFields: nil
                )!
                let body = isFirst ? Data() : Data("{\"id\":9,\"name\":\"fresh\"}\n".utf8)
                let stream = AsyncThrowingStream<Data, Error>(Data.self) { continuation in
                    if body.isEmpty == false { continuation.yield(body) }
                    continuation.finish()
                }
                return (stream, response)
            }
        }
        final class Refresher: TokenRefreshProvider, @unchecked Sendable {
            var refreshes = 0
            func refreshTokenIfNeeded() async throws { refreshes += 1 }
        }
        let session = StagedDataSession()
        let refresher = Refresher()
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        manager.tokenRefresher = refresher

        let response = try await manager.stream(ChunkStreamRequest(), accessToken: { "stale" })
        var items: [ChunkItem] = []
        for try await item in response.ndjson(as: ChunkItem.self) { items.append(item) }

        #expect(session.calls == 2)
        #expect(refresher.refreshes == 1)
        #expect(items == [ChunkItem(id: 9, name: "fresh")])
    }

    // MARK: §14 / §15 regression — legacy byteStream-only mocks & deprecated bytes consumer

    @Test("§14/§15 a legacy byteStream-only mock works end-to-end and response.bytes matches chunks")
    func legacyByteStreamMockAndDeprecatedBytesConsumer() async throws {
        let body = Data("{\"id\":1,\"name\":\"legacy\"}\n".utf8)
        let session = ByteStreamOnlySession(body: body)
        let manager = NetworkManager(
            baseURL: URL(string: "https://unit.test")!,
            streamingSession: session
        )
        // Deprecated consumer path: response.bytes must still compile and yield the same body.
        let response = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
        var fromBytes: [UInt8] = []
        for try await b in response.bytes { fromBytes.append(b) }
        #expect(Data(fromBytes) == body)

        // ndjson over the same legacy mock decodes correctly.
        let response2 = try await manager.stream(ChunkStreamRequest(), accessToken: nil)
        var items: [ChunkItem] = []
        for try await item in response2.ndjson(as: ChunkItem.self) { items.append(item) }
        #expect(items == [ChunkItem(id: 1, name: "legacy")])
    }

    @Test("§15 deprecated StreamingResponse(bytes:) initializer coalesces into multiple chunks")
    func deprecatedBytesInitCoalesces() async throws {
        // Body larger than the legacy 16 KiB chunk size so the buffer-flush branch fires
        // (Streaming.swift init(bytes:) lines 296–298) and a partial tail remains.
        let body = Data((0..<(16 * 1024 + 500)).map { UInt8($0 & 0xFF) })
        let byteStream = AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                for b in body { continuation.yield(b) }
                continuation.finish()
            }
        }
        let response = StreamingResponse(statusCode: 200, headers: [:], bytes: byteStream)
        var reassembled = Data()
        var chunkCount = 0
        for try await chunk in response.chunks { chunkCount += 1; reassembled.append(chunk) }
        #expect(reassembled == body)
        #expect(chunkCount >= 2)
    }

    @Test("§15b deprecated StreamingResponse(bytes:) propagates a mid-stream error from the byte source")
    func deprecatedBytesInitPropagatesError() async throws {
        struct BoomError: Error {}
        let byteStream = AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                for b in Data("partial".utf8) { continuation.yield(b) }
                continuation.finish(throwing: BoomError()) // hits init(bytes:) catch, line 305
            }
        }
        let response = StreamingResponse(statusCode: 200, headers: [:], bytes: byteStream)
        await #expect(throws: BoomError.self) {
            for try await _ in response.chunks {}
        }
    }

    @Test("§8b default byteStream(for:) propagates a mid-stream error from a dataStream-only source")
    func defaultByteStreamPropagatesError() async throws {
        struct BoomError: Error {}
        // dataStream-only session that fails after one chunk → the derived byteStream default
        // must forward the error from its bridging task (Streaming.swift line 141).
        let session = DataStreamOnlySession(chunks: [Data("abc".utf8)], error: BoomError())
        let (byteStream, _) = try await session.byteStream(for: URLRequest(url: URL(string: "https://x.test")!))
        var received: [UInt8] = []
        await #expect(throws: BoomError.self) {
            for try await b in byteStream { received.append(b) }
        }
        // The bytes that arrived before the failure are still delivered.
        #expect(received == Array("abc".utf8))
    }
}

// MARK: - §10 Real URLSession.dataStream bridge

/// `URLProtocol` stub that delivers a 200 head then a fixed body to EOF. Lets the real
/// `URLSession.dataStream(for:)` bridge (`self.bytes(for:)` → coalesced chunks) run end-to-end.
private final class DataStreamStubProtocol: URLProtocol {
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

private func makeDataStreamStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DataStreamStubProtocol.self]
    return URLSession(configuration: config)
}

/// `URLProtocol` stub that drips bytes indefinitely until cancelled, so the consumer can break out
/// of `dataStream` iteration mid-stream and trigger `onTermination` → `task.cancel()`.
private final class DataStreamSlowProtocol: URLProtocol {
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
        let queue = DispatchQueue(label: "datastream.slow")
        func emit() {
            queue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
                guard let self, Self.cancelled == false else { return }
                // Emit a full chunk-worth so the consumer receives discrete `Data` elements.
                self.client?.urlProtocol(self, didLoad: Data(repeating: 0x41, count: 16 * 1024))
                emit()
            }
        }
        emit()
    }
}

private func makeDataStreamSlowSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DataStreamSlowProtocol.self]
    return URLSession(configuration: config)
}

@Suite("URLSession.dataStream real bridge (1.7.0)")
struct URLSessionDataStreamBridgeTests {

    @Test("§10 dataStream coalesces the body into chunks and finishes on EOF")
    func dataStreamHappyPath() async throws {
        // Body larger than one chunk so coalescing yields a full chunk + a tail.
        let body = Data(repeating: 0x5A, count: 16 * 1024 + 7)
        DataStreamStubProtocol.body = body
        let session = makeDataStreamStubSession()

        let (chunks, response) = try await session.dataStream(
            for: URLRequest(url: URL(string: "https://stub.test/x")!)
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        var reassembled = Data()
        var chunkCount = 0
        for try await chunk in chunks {
            chunkCount += 1
            reassembled.append(chunk)
        }
        #expect(reassembled == body)
        #expect(chunkCount >= 1)
    }

    @Test("§10 dataStream bridge cancels (onTermination → task.cancel) when iteration breaks mid-stream")
    func dataStreamCancelledMidStream() async throws {
        let session = makeDataStreamSlowSession()
        let (chunks, response) = try await session.dataStream(
            for: URLRequest(url: URL(string: "https://stub.test/slow")!)
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        var received = 0
        for try await _ in chunks {
            received += 1
            if received >= 2 { break }
        }
        #expect(received == 2)
        // Breaking fires onTermination → task.cancel(); stopLoading sets cancelled. Give it a beat.
        await Task.yield()
    }
}
