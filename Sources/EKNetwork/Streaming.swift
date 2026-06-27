//
//  Streaming.swift
//  EKNetwork
//
//  Created by Emil Karimov on 09.05.2026.
//  Copyright © 2026 Emil Karimov. All rights reserved.
//
//  Streaming response support (NDJSON / SSE / chunked transfer-encoding).
//
//  This file is **purely additive**: it does not modify any existing public type and does not
//  change behaviour of `NetworkManager.send(_:)`. Existing callers of EKNetwork keep working
//  unchanged.
//
//  Why streaming lives here as a separate API:
//  ------------------------------------------
//  `send(_:)` decodes the full response body into a single `Decodable`. For protocols that emit
//  events as data arrives (NDJSON, Server-Sent Events, chunked log/streaming endpoints) the
//  caller needs to consume bytes as soon as the server flushes them. URLSession exposes
//  `bytes(for:)` for this; this file wraps it in the same request-construction pipeline used by
//  `send(_:)` (headers, access token, User-Agent, base URL, body), so the caller cannot
//  accidentally bypass the network stack and lose required headers.
//
//  Public surface introduced (since 1.6.0):
//      - `URLSessionStreamingProtocol`         — DI seam for the streaming session
//      - `NetworkStreaming` protocol           — abstraction for `stream(_:accessToken:)`
//      - `StreamingResponse`                   — value returned from `stream(_:accessToken:)`
//      - `StreamingError`                      — streaming-specific error cases
//      - `NetworkManager.stream(_:accessToken:)` — concrete implementation
//
//  since 1.7.0: chunks, dataStream(for:), init(...chunks:); bytes/byteStream/init(...bytes:) deprecated
//
//  Chunked streaming (since 1.7.0):
//  --------------------------------
//  The body is now exposed primarily as `AsyncThrowingStream<Data, Error>` (chunks) instead of
//  `AsyncThrowingStream<UInt8, Error>` (one byte per element). Byte-level yielding incurred a
//  per-byte `checkCancellation` + continuation overhead that scaled poorly for MB-sized streams.
//  Coalescing into ~16 KiB `Data` chunks reduces the per-element overhead by orders of magnitude.
//  `bytes` and `byteStream(for:)` remain available as deprecated derived wrappers, so existing
//  callers and mocks keep compiling (additive, minor release).
//

import os
import Foundation

// MARK: - URLSession streaming abstraction

/// Protocol abstraction for the streaming side of `URLSession`, allowing dependency injection
/// and unit-testing of `NetworkManager.stream(_:accessToken:)` without hitting the network.
///
/// The default conformance (provided by `URLSession`) bridges `URLSession.bytes(for:)` to
/// a fully `Sendable` `AsyncThrowingStream<Data, Error>` (coalesced chunks) so the type travels
/// safely across concurrency domains under Swift 6 strict concurrency.
///
/// Implement this protocol in tests to feed deterministic data into the streaming pipeline.
/// Conformers must implement **at least one** of `dataStream(for:)` / `byteStream(for:)`;
/// the protocol extension provides mutually-derived default implementations for the other.
public protocol URLSessionStreamingProtocol: Sendable {

    /// Issues `request` and returns the response head together with an async **data chunk** stream.
    ///
    /// This is the preferred entry point since 1.7.0: chunks coalesce many octets per element,
    /// avoiding the per-byte overhead of `byteStream(for:)`.
    ///
    /// - Important: The returned `URLResponse` is delivered **before** the body is fully received,
    ///   so callers can inspect `(response as? HTTPURLResponse)?.statusCode` and decide whether to
    ///   keep streaming or drain the body into an error payload.
    /// - Parameter request: The fully-prepared `URLRequest` (URL, method, headers, body).
    /// - Returns: A tuple of (`chunks`, `response`). `chunks` yields `Data` slices in the order
    ///   received. The stream finishes naturally on EOF and throws on transport errors.
    func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse)

    /// Issues `request` and returns the response head together with an async byte stream.
    ///
    /// - Important: The returned `URLResponse` is delivered **before** the body is fully received.
    /// - Parameter request: The fully-prepared `URLRequest` (URL, method, headers, body).
    /// - Returns: A tuple of (`bytes`, `response`). `bytes` yields raw octets in the order received.
    @available(*, deprecated, message: "Use dataStream(for:) — byte-by-byte streaming is inefficient for large bodies. byteStream(for:) is derived from dataStream(for:) and will be removed in a future major release.")
    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
}

extension URLSessionStreamingProtocol {

    /// Coalescing chunk size used by the bridge / default implementations (16 KiB).
    internal static var streamChunkSize: Int { 16 * 1024 }

    /// Default `dataStream(for:)` derived from `byteStream(for:)` by coalescing bytes into
    /// `streamChunkSize`-sized `Data` chunks. Conformers that implement `byteStream(for:)`
    /// directly get this for free.
    public func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        // Deliberately calls the (deprecated) byteStream requirement: a conformer that only
        // implements byteStream relies on this default. Recursion is impossible here because
        // any conformer providing byteStream cannot simultaneously rely on the byteStream
        // default (which derives from dataStream) — at least one is concrete.
        // The deprecation warning below is accepted consciously: the attribute targets external
        // callers, while this is the library's own mutually-derived default implementation.
        let (byteStream, response) = try await byteStream(for: request)
        let chunkSize = Self.streamChunkSize
        let stream = AsyncThrowingStream<Data, Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(chunkSize)
                    for try await byte in byteStream {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if buffer.isEmpty == false {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return (stream, response)
    }

    /// Default `byteStream(for:)` derived from `dataStream(for:)` by flattening each `Data` chunk
    /// into individual octets. Conformers that implement `dataStream(for:)` directly get this for
    /// free, preserving source compatibility for legacy consumers of `byteStream`.
    @available(*, deprecated, message: "Use dataStream(for:) — byte-by-byte streaming is inefficient for large bodies. byteStream(for:) is derived from dataStream(for:) and will be removed in a future major release.")
    public func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let (chunks, response) = try await dataStream(for: request)
        let stream = AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        try Task.checkCancellation()
                        for byte in chunk {
                            continuation.yield(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return (stream, response)
    }

}

extension URLSession: URLSessionStreamingProtocol {

    /// Concrete `dataStream(for:)` for `URLSession`: bridges `URLSession.bytes(for:)` (whose
    /// `AsyncBytes` is non-`Sendable` in some toolchains) into a `Sendable`
    /// `AsyncThrowingStream<Data, Error>`, coalescing bytes into `streamChunkSize`-sized chunks.
    ///
    /// - Important: This implementation calls `self.bytes(for:)` **directly** (not `self.byteStream`).
    ///   `byteStream` for `URLSession` is provided by the protocol-extension default, which derives
    ///   from `dataStream`. Calling `self.byteStream` here would create infinite mutual recursion;
    ///   `self.bytes(for:)` is the underlying Foundation primitive and breaks that cycle.
    public func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let (asyncBytes, response) = try await self.bytes(for: request)
        let chunkSize = Self.streamChunkSize
        let stream = AsyncThrowingStream<Data, Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(chunkSize)
                    for try await byte in asyncBytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if buffer.isEmpty == false {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return (stream, response)
    }
}

// MARK: - Errors

/// Errors produced by `NetworkManager.stream(_:accessToken:)` in addition to `HTTPError` /
/// `NetworkError` already used by `send(_:)`.
public enum StreamingError: Error, Equatable {

    /// The server response was not a valid `HTTPURLResponse`; cannot inspect the status code.
    case invalidResponse

    /// While buffering an error payload from a non-2xx response, the safety cap was hit
    /// (`maxErrorPayloadBytes`). Useful so a misbehaving server cannot OOM the client.
    case errorPayloadTooLarge(limitBytes: Int)
}

// MARK: - StreamingResponse

/// A streaming HTTP response: status code, headers, and an async data-chunk stream.
///
/// Returned from `NetworkManager.stream(_:accessToken:)` for endpoints that emit data as it is
/// produced (NDJSON, SSE, chunked transfer). Use one of the helpers (`lines()`, `ndjson(as:)`)
/// or iterate `chunks` directly.
///
/// Cancellation: the underlying network task is cancelled automatically when the consumer
/// breaks out of iteration or the surrounding `Task` is cancelled.
public struct StreamingResponse: Sendable {

    /// HTTP status code reported in the response head (always 2xx — non-2xx responses are
    /// transformed into `HTTPError` before this value is constructed).
    public let statusCode: Int

    /// Response headers, normalized to `[String: String]`.
    public let headers: [String: String]

    /// Raw `Data`-chunk stream of the response body. Each iteration step yields a slice of bytes
    /// (coalesced ~16 KiB) in the order it arrived. The stream finishes on EOF and throws on
    /// transport / cancellation errors.
    ///
    /// Consume via `for try await chunk in response.chunks` or use the convenience helpers below.
    public let chunks: AsyncThrowingStream<Data, Error>

    /// Raw octet stream of the response body, derived from `chunks`.
    ///
    /// - Warning: Deprecated in 1.7.0. Iterating byte-by-byte is inefficient for large bodies.
    ///   Prefer `chunks` (or the `lines()` / `ndjson(as:)` helpers). This computed wrapper
    ///   flattens each `Data` chunk into individual octets for source compatibility.
    @available(*, deprecated, message: "Use chunks (AsyncThrowingStream<Data, Error>) — byte-by-byte iteration is inefficient for large bodies. bytes is derived from chunks and will be removed in a future major release.")
    public var bytes: AsyncThrowingStream<UInt8, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream<UInt8, Error>(UInt8.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        try Task.checkCancellation()
                        for byte in chunk {
                            continuation.yield(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Initializes a `StreamingResponse` from a `Data`-chunk stream (primary, since 1.7.0).
    /// Marked `public` for testability — production code receives this value from
    /// `NetworkManager.stream(...)`.
    public init(
        statusCode: Int,
        headers: [String: String],
        chunks: AsyncThrowingStream<Data, Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.chunks = chunks
    }

    /// Initializes a `StreamingResponse` from a byte stream (legacy).
    ///
    /// - Warning: Deprecated in 1.7.0. Use `init(statusCode:headers:chunks:)`. This initializer
    ///   coalesces the incoming bytes into `Data` chunks to populate `chunks`.
    @available(*, deprecated, message: "Use init(statusCode:headers:chunks:) — initializing from a byte stream coalesces into chunks and will be removed in a future major release.")
    public init(
        statusCode: Int,
        headers: [String: String],
        bytes: AsyncThrowingStream<UInt8, Error>
    ) {
        let chunkSize = StreamingResponse.legacyChunkSize
        let chunks = AsyncThrowingStream<Data, Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(chunkSize)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if buffer.isEmpty == false {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        self.statusCode = statusCode
        self.headers = headers
        self.chunks = chunks
    }

    /// Coalescing chunk size for the legacy byte-stream initializer (16 KiB).
    private static var legacyChunkSize: Int { 16 * 1024 }

    /// Decodes the body as a stream of UTF-8 lines, splitting on `\n` and trimming a trailing `\r`.
    ///
    /// Empty lines are skipped (matches the NDJSON convention where a blank line is a no-op
    /// rather than an empty record). Lines that fail UTF-8 decoding are skipped silently to
    /// keep the stream resilient to multi-byte sequences split across TCP segments — bytes are
    /// buffered across chunk boundaries until a newline arrives, then the whole line is decoded
    /// best-effort.
    ///
    /// - Returns: An `AsyncThrowingStream<String, Error>` that yields one line per element.
    public func lines() -> AsyncThrowingStream<String, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream<String, Error>(String.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                var buffer = Data()
                buffer.reserveCapacity(1024)

                // Emits the accumulated `buffer` as one line: trims a trailing \r, skips empties,
                // decodes UTF-8 best-effort, and resets the buffer (keeping capacity).
                func emitLine() {
                    if buffer.last == 0x0D { buffer.removeLast() } // trim trailing \r (CRLF)
                    if buffer.isEmpty == false {
                        if let line = String(data: buffer, encoding: .utf8) {
                            continuation.yield(line)
                        }
                        buffer.removeAll(keepingCapacity: true)
                    }
                }

                do {
                    for try await chunk in chunks {
                        try Task.checkCancellation()
                        var searchStart = chunk.startIndex
                        while let newlineIndex = chunk[searchStart...].firstIndex(of: 0x0A) {
                            buffer.append(chunk[searchStart..<newlineIndex])
                            emitLine()
                            searchStart = chunk.index(after: newlineIndex)
                        }
                        // Carry the tail (after the last \n) across to the next chunk.
                        if searchStart < chunk.endIndex {
                            buffer.append(chunk[searchStart...])
                        }
                    }
                    // Flush a trailing line without a terminating newline.
                    emitLine()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Decodes each non-empty line of the body as an NDJSON record of type `Item`.
    ///
    /// One JSON object per line is the standard NDJSON convention used, for example, by
    /// streaming search endpoints, log shippers, and many ML inference servers.
    ///
    /// - Parameters:
    ///   - itemType: The decodable element type (passed for type inference clarity at call site).
    ///   - decoder: The decoder used for each line. Defaults to a fresh `JSONDecoder()`.
    /// - Returns: An `AsyncThrowingStream<Item, Error>` of decoded records. A single bad line
    ///   throws and finishes the stream — switch to `lines()` if you need lenient per-line
    ///   error recovery.
    public func ndjson<Item: Decodable & Sendable>(
        as itemType: Item.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) -> AsyncThrowingStream<Item, Error> {
        let lines = self.lines()
        return AsyncThrowingStream<Item, Error>(Item.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8) else { continue }
                        let item = try decoder.decode(Item.self, from: data)
                        continuation.yield(item)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// MARK: - NetworkStreaming protocol

/// Streaming counterpart of `NetworkManaging`.
///
/// Kept separate from `NetworkManaging` to preserve full source compatibility: existing mocks
/// that conform to `NetworkManaging` do not need to implement streaming. Production code uses
/// `NetworkManager`, which conforms to both protocols.
public protocol NetworkStreaming: AnyObject {

    /// Issues `request` and returns a `StreamingResponse` whose body can be consumed
    /// incrementally as the server emits data.
    ///
    /// The same request-construction pipeline as `send(_:)` is used: headers, access token,
    /// User-Agent and request body are applied via the manager's standard hooks. This is the
    /// single recommended way to obtain a streaming response — manually building a `URLRequest`
    /// in the app layer is discouraged because it bypasses required headers (e.g. device
    /// identifiers, custom auth, telemetry).
    ///
    /// - Parameters:
    ///   - request: A `NetworkRequest` describing the endpoint. The `Response` associated type
    ///     is **not used** for streaming and may be set to `EmptyResponse` for clarity.
    ///   - accessToken: Closure providing the current access token. Same semantics as `send(_:)`.
    /// - Returns: A `StreamingResponse` with a 2xx status code; non-2xx responses are converted
    ///   into `HTTPError` (or the request's `errorDecoder` output) and thrown.
    /// - Throws: `HTTPError`, `NetworkError`, `StreamingError`, `URLError`, or `CancellationError`.
    func stream<T: NetworkRequest>(
        _ request: T,
        accessToken: (() -> String?)?
    ) async throws -> StreamingResponse
}

// MARK: - NetworkManager + streaming

extension NetworkManager: NetworkStreaming {

    /// Maximum number of bytes buffered when draining the body of a non-2xx streaming response
    /// to construct an `HTTPError`. Anything beyond this is dropped and `StreamingError
    /// .errorPayloadTooLarge` is thrown so a misbehaving server cannot exhaust client memory.
    private static var maxErrorPayloadBytes: Int { 1 * 1024 * 1024 } // 1 MiB

    /// Issues a streaming request. See `NetworkStreaming.stream(_:accessToken:)` for full docs.
    ///
    /// Behaviour:
    /// * Reuses `buildURLRequest(_:accessToken:)` so headers/body match `send(_:)` byte-for-byte.
    /// * On HTTP 401, if `request.allowsRetry == true`, calls the configured `tokenRefresher`
    ///   and retries the request **once**. Mid-stream 401s are not retried (the upstream has
    ///   already started sending body bytes by definition).
    /// * On any other non-2xx, drains up to `maxErrorPayloadBytes` of the body, runs
    ///   `request.errorDecoder` if provided, and throws either the custom error or `HTTPError`.
    /// * Uses `streamingSession` (resolved at init time) for the data transfer.
    public func stream<T: NetworkRequest>(
        _ request: T,
        accessToken: (() -> String?)?
    ) async throws -> StreamingResponse {
        return try await performStream(request, accessToken: accessToken, allowRefreshRetry: true)
    }

    private func performStream<T: NetworkRequest>(
        _ request: T,
        accessToken: (() -> String?)?,
        allowRefreshRetry: Bool
    ) async throws -> StreamingResponse {
        try Task.checkCancellation()

        logger.info("➡️ [NETWORK STREAM] [\(request.method.rawValue)] \(request.path, privacy: .private)")

        let urlRequest = try buildURLRequest(request, accessToken: accessToken)
        let (chunks, urlResponse) = try await streamingSession.dataStream(for: urlRequest)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw StreamingError.invalidResponse
        }

        let statusCode = httpResponse.statusCode

        // 401 — refresh once and retry (only if the upstream has not yet started streaming body).
        // Only when a tokenRefresher is configured: without one the retry is identical to the
        // first request and yields a guaranteed second 401 — a useless round-trip. Mirrors `send`.
        if statusCode == 401, request.allowsRetry, allowRefreshRetry, tokenRefresher != nil {
            // Drain chunks (small payload expected for 401) so the connection is released cleanly.
            _ = try? await Self.drain(chunks: chunks, limit: Self.maxErrorPayloadBytes)
            try await refreshTokenIfNeeded()
            return try await performStream(request, accessToken: accessToken, allowRefreshRetry: false)
        }

        // Non-2xx — drain a bounded slice for diagnostics, throw HTTPError or custom-decoded error.
        if !(200..<300).contains(statusCode) {
            let payload = try await Self.drain(chunks: chunks, limit: Self.maxErrorPayloadBytes)
            if statusCode == 401 {
                if let customError = request.errorDecoder?(payload) {
                    throw customError
                }
                throw NetworkError.unauthorized
            }
            if let customError = request.errorDecoder?(payload) {
                throw customError
            }
            throw HTTPError(
                statusCode: statusCode,
                data: payload,
                headers: httpResponse.allHeaderFields
            )
        }

        // Success — hand the live data stream to the caller.
        let normalizedHeaders: [String: String] = httpResponse.allHeaderFields
            .reduce(into: [:]) { acc, pair in
                guard let key = pair.key as? String else { return }
                acc[key] = pair.value as? String ?? String(describing: pair.value)
            }

        logger.info("✅ [NETWORK STREAM] [\(request.method.rawValue)] \(request.path, privacy: .private) STARTED status=\(statusCode)")

        return StreamingResponse(
            statusCode: statusCode,
            headers: normalizedHeaders,
            chunks: chunks
        )
    }

    /// Drains an `AsyncThrowingStream<Data, Error>` into `Data`, capping the buffered size.
    /// Used to materialise a small error payload from a non-2xx streaming response without
    /// risking unbounded memory growth.
    ///
    /// A payload of exactly `limit` bytes is accepted; only `> limit` triggers
    /// `StreamingError.errorPayloadTooLarge`.
    private static func drain(
        chunks: AsyncThrowingStream<Data, Error>,
        limit: Int
    ) async throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(min(limit, 16 * 1024))
        for try await chunk in chunks {
            if buffer.count + chunk.count > limit {
                // Top up to the limit for diagnostics, then reject.
                let remaining = limit - buffer.count
                if remaining > 0 {
                    buffer.append(chunk.prefix(remaining))
                }
                throw StreamingError.errorPayloadTooLarge(limitBytes: limit)
            }
            buffer.append(chunk)
        }
        return buffer
    }
}
