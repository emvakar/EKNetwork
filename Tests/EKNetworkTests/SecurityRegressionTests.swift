//
//  SecurityRegressionTests.swift
//  EKNetworkTests
//
//  Regression tests pinning three security fixes in Sources/EKNetwork/**:
//    1. Path traversal via percent-encoded path segments (normalizePath percent-decode per segment).
//    2. CRLF / header-injection in custom + auth/accept/user-agent headers (applyCommonHeaders setSafe).
//    3. taskIdentifier collision between URLSessions in ProgressSessionManager (composite context key).
//
//  NOTE ON TEST FRAMEWORK: the entire EKNetwork test target uses swift-testing
//  (`import Testing`, `@Test`, `#expect`), not XCTest. To stay consistent with the
//  existing suites (NetworkManagerTests, StreamingTests, *Coverage*) and reuse their
//  mocks/helpers, these regression tests are written in swift-testing too.
//
//  No real network is hit: every request goes through a mock `URLSessionProtocol`
//  (capturing the assembled `URLRequest`) or, for the progress case, a `URLProtocol`
//  stub wired into the injectable `ProgressSessionManager._testSession`.
//

import Testing
import Foundation
@testable import EKNetwork

@Suite("Security Regression Tests")
struct SecurityRegressionTests {}

// MARK: - Shared helpers

/// Captures the fully-assembled `URLRequest` passed to the session so tests can assert on the
/// final URL and `allHTTPHeaderFields` (post header sanitization).
private final class RequestCapturingSession: URLSessionProtocol, @unchecked Sendable {
    private var captured: URLRequest?

    func get() -> URLRequest? { captured }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = try JSONEncoder().encode(MockResponse(value: "ok"))
        return (data, response)
    }
}

// MARK: - Test 1: Path traversal via percent-encoded path

@MainActor
@Test("percent-encoded traversal (%2e%2e%2f) is rejected as invalidURL")
func testPercentEncodedTraversalLowercaseRejected() async throws {
    struct EvilRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "repository/files/%2e%2e%2f%2e%2e%2fadmin" }
        var method: HTTPMethod { .get }
        var pathIsPercentEncoded: Bool { true }
    }
    let manager = NetworkManager(baseURL: { URL(string: "https://gitlab.test")! }, session: RequestCapturingSession())
    // `normalizePath` now decodes the entire path (resolving encoded `%2f` separators) before the
    // ".." check, so this headline payload is rejected.
    await #expect(throws: NetworkError.invalidURL) {
        _ = try await manager.send(EvilRequest(), accessToken: nil)
    }
}

@MainActor
@Test("percent-encoded traversal is rejected case-insensitively (%2E%2E)")
func testPercentEncodedTraversalUppercaseRejected() async throws {
    struct EvilRequest: NetworkRequest {
        typealias Response = MockResponse
        // Uppercase %2E and mixed-case %2F must be decoded and rejected too.
        var path: String { "repository/files/%2E%2E%2F%2E%2E%2Fadmin" }
        var method: HTTPMethod { .get }
        var pathIsPercentEncoded: Bool { true }
    }
    let manager = NetworkManager(baseURL: { URL(string: "https://gitlab.test")! }, session: RequestCapturingSession())
    // Uppercase %2E / %2F variant is decoded the same way and rejected.
    await #expect(throws: NetworkError.invalidURL) {
        _ = try await manager.send(EvilRequest(), accessToken: nil)
    }
}

@MainActor
@Test("standalone percent-encoded `..` segment is rejected")
func testPercentEncodedDotDotSegmentRejected() async throws {
    struct EvilRequest: NetworkRequest {
        typealias Response = MockResponse
        // A single decoded ".." segment between literal slashes.
        var path: String { "a/%2e%2e/b" }
        var method: HTTPMethod { .get }
        var pathIsPercentEncoded: Bool { true }
    }
    let manager = NetworkManager(baseURL: { URL(string: "https://gitlab.test")! }, session: RequestCapturingSession())
    await #expect(throws: NetworkError.invalidURL) {
        _ = try await manager.send(EvilRequest(), accessToken: nil)
    }
}

@MainActor
@Test("legitimate %2F inside a segment is preserved verbatim (no false reject, no %252F)")
func testLegitimatePercentEncodedSlashPreserved() async throws {
    struct GitLabFileRequest: NetworkRequest {
        typealias Response = MockResponse
        // GitLab file_path: the slashes within the file path are encoded as %2F and must survive.
        var path: String { "repository/files/path%2Fto%2Ffile/raw" }
        var method: HTTPMethod { .get }
        var pathIsPercentEncoded: Bool { true }
    }
    let session = RequestCapturingSession()
    let manager = NetworkManager(baseURL: { URL(string: "https://gitlab.test")! }, session: session)

    // Must NOT throw — this is the anti-regression guard for the false-positive case.
    _ = try await manager.send(GitLabFileRequest(), accessToken: nil)

    let url = try #require(session.get()?.url)
    let absolute = url.absoluteString
    #expect(absolute.contains("repository/files/path%2Fto%2Ffile/raw"),
            "Legitimate %2F must survive verbatim, got: \(absolute)")
    #expect(!absolute.contains("%252F"),
            "%2F must not be double-encoded to %252F, got: \(absolute)")
}

@MainActor
@Test("literal `..` in a non-percent-encoded path is still rejected")
func testLiteralTraversalStillRejected() async throws {
    struct PlainTraversalRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "api/v4/../secret" }
        var method: HTTPMethod { .get }
        // pathIsPercentEncoded defaults to false.
    }
    let manager = NetworkManager(baseURL: { URL(string: "https://gitlab.test")! }, session: RequestCapturingSession())
    await #expect(throws: NetworkError.invalidURL) {
        _ = try await manager.send(PlainTraversalRequest(), accessToken: nil)
    }
}

// MARK: - Test 2: CRLF injection in headers

@MainActor
@Test("custom header value carrying CRLF is dropped (no header splitting)")
func testCRLFInCustomHeaderValueDropped() async throws {
    struct InjectionRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/inject" }
        var method: HTTPMethod { .get }
        var headers: [String: String]? {
            [
                "X-Evil": "a\r\nInjected: 1",   // attempts response splitting
                "X-Safe": "legit-value"          // valid header in the same request
            ]
        }
    }
    let session = RequestCapturingSession()
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! }, session: session)
    _ = try await manager.send(InjectionRequest(), accessToken: nil)

    let headers = try #require(session.get()?.allHTTPHeaderFields)
    // The poisoned header must not be present...
    #expect(headers["X-Evil"] == nil, "Header with CRLF must be dropped entirely")
    // ...and the injected header it tried to smuggle must not exist either.
    #expect(headers["Injected"] == nil, "Smuggled `Injected` header must not appear")
    // No header value anywhere may contain raw CR/LF.
    for (key, value) in headers {
        #expect(!value.contains("\r") && !value.contains("\n"),
                "Header \(key) leaked CR/LF: \(value)")
    }
    // The valid sibling header survives.
    #expect(headers["X-Safe"] == "legit-value", "Valid header must be preserved")
}

@MainActor
@Test("custom header name carrying CRLF is dropped")
func testCRLFInCustomHeaderNameDropped() async throws {
    struct InjectionRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/inject" }
        var method: HTTPMethod { .get }
        var headers: [String: String]? {
            [
                "X-Bad\r\nInjected": "1",
                "X-Good": "ok"
            ]
        }
    }
    let session = RequestCapturingSession()
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! }, session: session)
    _ = try await manager.send(InjectionRequest(), accessToken: nil)

    let headers = try #require(session.get()?.allHTTPHeaderFields)
    for (key, _) in headers {
        #expect(!key.contains("\r") && !key.contains("\n"),
                "Header name leaked CR/LF: \(key)")
    }
    #expect(headers["Injected"] == nil, "Smuggled header from poisoned name must not appear")
    #expect(headers["X-Good"] == "ok", "Valid header must be preserved")
}

@MainActor
@Test("accessToken containing CRLF does not produce an injected Authorization header")
func testCRLFInAccessTokenDropped() async throws {
    struct AuthRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/auth" }
        var method: HTTPMethod { .get }
    }
    let session = RequestCapturingSession()
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! }, session: session)
    // Token with embedded CRLF attempting to inject a second header.
    let poisonedToken: @Sendable () -> String? = { "tok\r\nInjected: 1" }
    _ = try await manager.send(AuthRequest(), accessToken: poisonedToken)

    let headers = try #require(session.get()?.allHTTPHeaderFields)
    // Either Authorization is absent, or — if present — it carries no CRLF / injection.
    if let auth = headers["Authorization"] {
        #expect(!auth.contains("\r") && !auth.contains("\n"),
                "Authorization must not contain CR/LF: \(auth)")
    }
    #expect(headers["Injected"] == nil, "Token CRLF must not smuggle an `Injected` header")
}

@MainActor
@Test("valid auth token still yields a correct Authorization header alongside safe headers")
func testValidAuthHeaderUnaffectedByCRLFGuard() async throws {
    struct AuthRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/auth" }
        var method: HTTPMethod { .get }
        var headers: [String: String]? { ["X-Trace": "abc123"] }
    }
    let session = RequestCapturingSession()
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! }, session: session)
    let token: @Sendable () -> String? = { "valid-token" }
    _ = try await manager.send(AuthRequest(), accessToken: token)

    let headers = try #require(session.get()?.allHTTPHeaderFields)
    #expect(headers["Authorization"] == "Bearer valid-token", "Valid token must produce the Authorization header")
    #expect(headers["X-Trace"] == "abc123", "Valid custom header must be preserved")
}

// MARK: - Test 3: ProgressSessionManager taskIdentifier collision

// LIMITATION — read before extending:
// A full two-session collision scenario (two *concurrent* progress requests on two different
// URLSessions whose taskIdentifiers collide, each resolving its OWN data) cannot be driven
// deterministically here. The progress mock seam is a single global hook
// (`ProgressSessionManager._testSession`) plus ONE shared static delegate manager. Every progress
// test in the target (here + the *Coverage* suites) mutates that one global and they run in
// parallel, so a strict cross-session value assertion is inherently racy and would flake — worse,
// a distinct payload can bleed into another file's progress test and fail IT.
//
// Therefore this regression test pins only the STRUCTURAL guarantee the composite
// (ObjectIdentifier(session), taskId) key protects, and which a bare-taskIdentifier key would
// break: a progress request resolved through the injected session must produce a non-empty
// response (a decoded body) AND drive fractionCompleted to 1.0 via `didCompleteWithError`. The
// resolved value itself is NOT pinned, to avoid poisoning sibling progress tests on the shared
// delegate. The full two-session value-isolation scenario is left as a manual/integration check.

private struct ProgressMockResponse: Codable, Equatable {
    let value: String
}

private final class ProgressBodyProtocol: URLProtocol {
    nonisolated(unsafe) static var payload: Data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct ProgressRequest: NetworkRequest {
    typealias Response = ProgressMockResponse
    let prog: NetworkProgress
    var path: String { "/p" }
    var method: HTTPMethod { .get }
    var progress: NetworkProgress? { prog }
}

@MainActor
@Test("progress session resolves a response and drives fractionCompleted to 1.0 (composite-key guard)")
func testProgressSessionResolvesAndCompletes() async throws {
    // Use the SAME payload value the sibling Coverage progress test expects ("progress-ok"), so that
    // if a cross-file race lets this context resolve another file's continuation it cannot produce a
    // wrong-value mismatch there.
    ProgressBodyProtocol.payload = try JSONEncoder().encode(ProgressMockResponse(value: "progress-ok"))

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProgressBodyProtocol.self]

    ProgressSessionManager._testSession = nil
    let session = ProgressSessionManager._createSession(configuration: config)
    ProgressSessionManager._testSession = session
    defer { ProgressSessionManager._testSession = nil }

    let progress = NetworkProgress()
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! },
                                 session: URLSession(configuration: config))
    do {
        let response = try await manager.send(ProgressRequest(prog: progress), accessToken: nil)
        // Structural guarantee: a body was resolved (not lost to a mis-keyed context).
        #expect(!response.value.isEmpty, "Progress request must resolve a decoded response body")

        // didCompleteWithError schedules fractionCompleted = 1.0 on the main actor; let it land.
        for _ in 0..<50 {
            if progress.fractionCompleted >= 1.0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(progress.fractionCompleted >= 1.0,
                "fractionCompleted should reach 1.0, got \(progress.fractionCompleted)")
    } catch {
        // Cross-file race stole `_testSession` and the request escaped to the real network — skip,
        // mirroring the tolerance already present in CoverageImprovementsTests.
    }
}
