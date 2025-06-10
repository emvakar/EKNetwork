import Testing
import Foundation
@testable import EKNetwork

struct MockResponse: Codable, Equatable {
    let value: String
}

struct MockRequest: NetworkRequest {
    typealias Response = MockResponse

    var path: String { "/test" }
    var method: HTTPMethod { .get }
}

final class MockSession: URLProtocol {

    nonisolated(unsafe) static var testData: Data?
    nonisolated(unsafe) static var testResponse: HTTPURLResponse?
    nonisolated(unsafe) static var testError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let data = MockSession.testData {
            client?.urlProtocol(self, didLoad: data)
        }
        if let response = MockSession.testResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let error = MockSession.testError {
            client?.urlProtocol(self, didFailWithError: error)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Test("request should return expected value") func testRequestSuccess() async throws {
    let expected = MockResponse(value: "ok")
    let data = try JSONEncoder().encode(expected)

    MockSession.testData = data
    MockSession.testResponse = HTTPURLResponse(url: URL(string: "https://test.com/test")!,
                                               statusCode: 200,
                                               httpVersion: nil,
                                               headerFields: nil)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockSession.self]

    let manager = NetworkManager(
        baseURL: URL(string: "https://test.com")!,
        session: URLSession(configuration: config)
    )

    let result = try await manager.send(MockRequest())
    #expect(result == expected)
}

@MainActor
@Test("request should throw if session returns error") func testRequestFailure() async throws {
    struct DummyError: Error { }
    MockSession.testError = DummyError()

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockSession.self]

    let manager = NetworkManager(
        baseURL: URL(string: "https://test.com")!,
        session: URLSession(configuration: config)
    )

    do {
        let response = try await manager.send(MockRequest())
        #expect(Bool(false))
    } catch let err {
        #expect(Bool(true))
    }
}

@MainActor
@Test("should retry up to maxRetryCount on retryable errors") func testRetryPolicyRetries() async throws {
    class CountingSession: URLProtocol {
        static var callCount = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            CountingSession.callCount += 1
            let error = URLError(.timedOut)
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    CountingSession.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CountingSession.self]
    struct RetryRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/test" }
        var method: HTTPMethod { .get }
        var retryPolicy: RetryPolicy { RetryPolicy(maxRetryCount: 2, delay: 0.1) { _ in true } }
    }
    let manager = NetworkManager(baseURL: URL(string: "https://test.com")!, session: URLSession(configuration: config))
    do {
        _ = try await manager.send(RetryRequest())
        #expect(false, "Should throw after retries are exhausted")
    } catch {
        #expect(CountingSession.callCount == 3, "Should try 1 original + 2 retries")
    }
}

@MainActor
@Test("should NOT retry on non-retryable errors") func testRetryPolicyNoRetryOnNonRetryableError() async throws {
    class UnauthorizedSession: URLProtocol {
        static var callCount = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            UnauthorizedSession.callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    UnauthorizedSession.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UnauthorizedSession.self]

    struct UnauthorizedRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/test" }
        var method: HTTPMethod { .get }
        var retryPolicy: RetryPolicy { RetryPolicy(maxRetryCount: 5, delay: 0.1) { _ in true } }
        var allowsRetry: Bool { false }
    }
    let manager = NetworkManager(baseURL: URL(string: "https://test.com")!, session: URLSession(configuration: config))
    do {
        _ = try await manager.send(UnauthorizedRequest())
        #expect(false, "Should throw unauthorized error")
    } catch {
        #expect(UnauthorizedSession.callCount == 1, "Should not retry on unauthorized")
    }
}

@MainActor
@Test("should respect custom shouldRetry closure") func testCustomShouldRetryClosure() async throws {
    class CustomError: Error {}
    class CustomSession: URLProtocol {
        static var callCount = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            CustomSession.callCount += 1
            client?.urlProtocol(self, didFailWithError: CustomError())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    CustomSession.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CustomSession.self]

    struct CustomRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/test" }
        var method: HTTPMethod { .get }
        var retryPolicy: RetryPolicy {
            RetryPolicy(maxRetryCount: 5, delay: 0.1) { error in
                // Only retry if error is not CustomError
                !(error is CustomError)
            }
        }
    }
    let manager = NetworkManager(baseURL: URL(string: "https://test.com")!, session: URLSession(configuration: config))
    do {
        _ = try await manager.send(CustomRequest())
        #expect(false, "Should throw after single fail due to shouldRetry returning false")
    } catch {
        #expect(CustomSession.callCount == 1, "Should not retry when shouldRetry returns false")
    }
}
