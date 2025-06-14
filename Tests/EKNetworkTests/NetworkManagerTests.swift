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
    actor URLBox {
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
        static var urlBox: URLBox?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Task { await Self.urlBox?.set(request.url) }
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
    let result = try await manager.send(MockRequest())
    let lastURL = await urlBox.get()
    #expect(result == MockResponse(value: "result"), "Manager should decode the response correctly")
    #expect(lastURL == URLCheckingSession.expectedURL, "Should form URL by joining baseURL and path")
}
