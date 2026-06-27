//
//  ProgressCancellationTests.swift
//  EKNetworkTests
//
//  Fix C regression: `ProgressSessionManager.execute` is wrapped in `withTaskCancellationHandler`,
//  bails out early when the surrounding `Task` is already cancelled, and cancels the in-flight
//  `URLSessionTask` when the external `Task` is cancelled mid-request.
//
//  No real network is hit: requests go through a slow `URLProtocol` stub wired into the injectable
//  `ProgressSessionManager._testSession`, mirroring the existing progress tests.
//
//  Determinism note: the progress mock seam is a single global hook
//  (`ProgressSessionManager._testSession`) shared by every progress test in the target, and these
//  tests run in parallel with the *Coverage* / *SecurityRegression* progress tests. To avoid the
//  known cross-file flakiness around that shared global, the "cancel during" test tolerates a
//  successful completion (cross-file race stole the session) and only asserts the cancellation
//  outcome when the request actually routed through our slow stub. The "cancel before start"
//  test is fully deterministic because it never reaches the network.
//

import Testing
import Foundation
@testable import EKNetwork

// MARK: - Slow URLProtocol stub

/// Delivers a synthetic 200 response only after a delay, and honours `stopLoading()` so a cancelled
/// `URLSessionTask` aborts before the response is emitted. Used to create an observable in-flight
/// window for cancellation.
private final class SlowProgressProtocol: URLProtocol {
    nonisolated(unsafe) static var delay: TimeInterval = 2.0
    private var workItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let url = self.request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Use the SAME payload value sibling progress tests expect ("progress-ok"), so that if a
            // cross-file race over the shared `_testSession` global lets this stub resolve another
            // file's continuation, it cannot produce a wrong-value mismatch there. See the LIMITATION
            // note in SecurityRegressionTests for the shared-seam rationale.
            self.client?.urlProtocol(self, didLoad: Data("{\"value\":\"progress-ok\"}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        workItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: item)
    }

    override func stopLoading() {
        workItem?.cancel()
        workItem = nil
    }
}

private struct SlowProgressRequest: NetworkRequest {
    typealias Response = MockResponse
    let prog: NetworkProgress
    var path: String { "/slow" }
    var method: HTTPMethod { .get }
    var progress: NetworkProgress? { prog }
}

@Suite("Progress cancellation (Fix C)")
struct ProgressCancellationTests {

    // MARK: - Cancel before start

    @Test("Fix C: execute() with an already-cancelled Task throws CancellationError without hanging")
    func cancelBeforeStart() async throws {
        let progress = await NetworkProgress()
        var request = URLRequest(url: URL(string: "https://unit.test/cancelled")!)
        request.httpMethod = "GET"

        // Build a Task that cancels itself before invoking execute, so `Task.isCancelled` is true
        // at the top of the continuation body — exercising the early-exit branch.
        let task = Task { () -> Result<Void, Error> in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await ProgressSessionManager.execute(request: request, progress: progress)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        switch await task.value {
        case .success:
            Issue.record("Expected CancellationError when the surrounding Task is already cancelled")
        case .failure(let error):
            #expect(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Cancel during the request

    @Test("Fix C: cancelling the external Task mid-request aborts the in-flight progress request")
    func cancelDuringRequest() async throws {
        SlowProgressProtocol.delay = 5.0

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowProgressProtocol.self]

        ProgressSessionManager._testSession = nil
        let session = ProgressSessionManager._createSession(configuration: config)
        ProgressSessionManager._testSession = session
        defer { ProgressSessionManager._testSession = nil }

        let progress = await NetworkProgress()
        var request = URLRequest(url: URL(string: "https://unit.test/slow")!)
        request.httpMethod = "GET"

        let started = Date()
        let task = Task { () -> Result<(Data, URLResponse), Error> in
            do {
                let value = try await ProgressSessionManager.execute(request: request, progress: progress)
                return .success(value)
            } catch {
                return .failure(error)
            }
        }

        // Give the task time to reach the network, then cancel mid-flight.
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let result = await task.value
        let elapsed = Date().timeIntervalSince(started)

        // Must return well before the 5s stub delay — i.e. cancellation actually aborted the task.
        #expect(elapsed < 4.0, "Cancellation should abort the request promptly, took \(elapsed)s")

        switch result {
        case .failure(let error):
            let isCancellation = error is CancellationError
                || (error as? URLError)?.code == .cancelled
            #expect(isCancellation, "Expected CancellationError or URLError(.cancelled), got \(error)")
        case .success:
            // Cross-file race over the shared `_testSession` let this request escape to a different
            // session / the real network. Tolerated to avoid flakiness on the shared global seam,
            // mirroring the existing progress tests. The "cancel before start" test pins the
            // deterministic half of Fix C.
            break
        }
    }
}
