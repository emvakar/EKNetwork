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

@MainActor
@Test("request forms correct URL and returns value")
func testURLFormationAndValue() async throws {
    final class URLBox: @unchecked Sendable {
        private var url: URL? = nil
        func set(_ new: URL?) { url = new }
        func get() -> URL? { url }
    }
    let urlBox = URLBox()

    class URLCheckingSession: URLProtocol {
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "result"))
        }()
        static let expectedURL = URL(string: "https://unit.test/test")!
        nonisolated(unsafe) static var urlBox: URLBox?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.urlBox?.set(request.url)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLCheckingSession.self]
    let base = URL(string: "https://unit.test")!
    URLCheckingSession.urlBox = urlBox
    let manager = NetworkManager(baseURL: base, session: URLSession(configuration: config))
    let result = try await manager.send(MockRequest(), accessToken: nil)
    let lastURL = urlBox.get()
    #expect(result == MockResponse(value: "result"), "Manager should decode the response correctly")
    #expect(lastURL == URLCheckingSession.expectedURL, "Should form URL by joining baseURL and path")
}

@MainActor
@Test("baseURL can be read")
func testBaseURLCanBeRead() async throws {
    let base = URL(string: "https://api.example.com")!
    let manager = NetworkManager(baseURL: base)
    #expect(manager.baseURL == base, "Should be able to read the base URL")
}

@MainActor
@Test("baseURL can be updated and affects subsequent requests")
func testBaseURLUpdate() async throws {
    final class URLBox: @unchecked Sendable {
        private var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
        func getAll() -> [URL] { urls }
    }
    let urlBox = URLBox()

    class URLTrackingSession: URLProtocol {
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "success"))
        }()
        nonisolated(unsafe) static var urlBox: URLBox?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let url = request.url {
                Self.urlBox?.add(url)
            }
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLTrackingSession.self]
    let initialBase = URL(string: "https://api-v1.example.com")!
    URLTrackingSession.urlBox = urlBox
    let manager = NetworkManager(baseURL: initialBase, session: URLSession(configuration: config))
    
    // First request with initial base URL
    _ = try await manager.send(MockRequest(), accessToken: nil)
    
    // Update base URL
    let newBase = URL(string: "https://api-v2.example.com")!
    manager.updateBaseURL(newBase)
    
    // Verify base URL was updated
    #expect(manager.baseURL == newBase, "Base URL should be updated")
    
    // Second request with new base URL
    _ = try await manager.send(MockRequest(), accessToken: nil)
    
    // Verify both URLs were used
    let capturedURLs = urlBox.getAll()
    #expect(capturedURLs.count == 2, "Should have made two requests")
    #expect(capturedURLs[0].absoluteString.hasPrefix("https://api-v1.example.com"), "First request should use old base URL")
    #expect(capturedURLs[1].absoluteString.hasPrefix("https://api-v2.example.com"), "Second request should use new base URL")
}
