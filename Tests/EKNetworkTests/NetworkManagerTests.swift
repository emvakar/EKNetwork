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

struct StatusOnlyRequest: NetworkRequest {
    typealias Response = StatusCodeResponse
    var path: String { "/status" }
    var method: HTTPMethod { .post }
}

struct EmptyRequest: NetworkRequest {
    typealias Response = EmptyResponse
    var path: String { "/empty" }
    var method: HTTPMethod { .delete }
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
@Test("status only responses can be consumed")
func testStatusOnlyResponse() async throws {
    class StatusOnlyProtocol: URLProtocol {
        nonisolated(unsafe) static var responseHeaders: [String: String] = ["X-Debug": "true"]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: StatusOnlyProtocol.responseHeaders)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StatusOnlyProtocol.self]
    let base = URL(string: "https://unit.test")!
    let manager = NetworkManager(baseURL: base, session: URLSession(configuration: config))
    let response = try await manager.send(StatusOnlyRequest(), accessToken: nil)
    #expect(response.statusCode == 204, "Should surface HTTP status code if body is empty")
    #expect(response.headers["X-Debug"] == "true", "Headers should be preserved")
}

@MainActor
@Test("empty responses succeed when body is empty")
func testEmptyResponseHandling() async throws {
    class EmptyProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [EmptyProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://unit.test")!, session: URLSession(configuration: config))
    let result = try await manager.send(EmptyRequest(), accessToken: nil)
    #expect(result == EmptyResponse(), "Empty responses should not throw when body is empty")
}

@MainActor
@Test("authorization header from request is preserved")
func testAuthorizationHeaderNotOverwritten() async throws {
    final class HeaderBox: @unchecked Sendable {
        private var value: String?
        func set(_ newValue: String?) { value = newValue }
        func get() -> String? { value }
    }
    let headerBox = HeaderBox()

    struct AuthRequest: NetworkRequest {
        struct Response: Codable { let ok: Bool }
        var path: String { "/auth" }
        var method: HTTPMethod { .get }
        var headers: [String: String]? { ["Authorization": "Custom abc"] }
    }

    class CaptureProtocol: URLProtocol {
        nonisolated(unsafe) static var headerBox: HeaderBox?
        static let data: Data = {
            try! JSONEncoder().encode(AuthRequest.Response(ok: true))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.headerBox?.set(request.value(forHTTPHeaderField: "Authorization"))
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CaptureProtocol.self]
    CaptureProtocol.headerBox = headerBox
    let manager = NetworkManager(baseURL: URL(string: "https://unit.test")!, session: URLSession(configuration: config))
    let tokenProvider: @Sendable () -> String? = { "ignored" }
    let response = try await manager.send(AuthRequest(), accessToken: tokenProvider)
    #expect(response.ok, "Should decode payload")
    #expect(headerBox.get() == "Custom abc", "Authorization header from request should remain untouched")
}

@MainActor
@Test("json encoder customization is respected")
func testCustomJSONEncoderUsage() async throws {
    final class BodyBox: @unchecked Sendable {
        private var data: Data?
        func set(_ new: Data?) { data = new }
        func get() -> Data? { data }
    }
    let bodyBox = BodyBox()

    struct EncoderRequest: NetworkRequest {
        struct Payload: Encodable {
            let date: Date
        }
        struct Response: Codable { let ok: Bool }
        var path: String { "/encode" }
        var method: HTTPMethod { .post }
        var body: RequestBody? {
            RequestBody(encodable: Payload(date: Date(timeIntervalSince1970: 0)))
        }
        var jsonEncoder: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            return encoder
        }
    }

    class EncoderProtocol: URLProtocol {
        nonisolated(unsafe) static var bodyBox: BodyBox?
        static let data: Data = {
            try! JSONEncoder().encode(EncoderRequest.Response(ok: true))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let body = request.httpBody {
                Self.bodyBox?.set(body)
            } else if let stream = request.httpBodyStream {
                let bufferSize = 1024
                var data = Data()
                stream.open()
                defer { stream.close() }
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 {
                        data.append(buffer, count: read)
                    } else {
                        break
                    }
                }
                Self.bodyBox?.set(data)
            }
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [EncoderProtocol.self]
    EncoderProtocol.bodyBox = bodyBox
    let manager = NetworkManager(baseURL: URL(string: "https://unit.test")!, session: URLSession(configuration: config))
    let response = try await manager.send(EncoderRequest(), accessToken: nil)
    #expect(response.ok, "Should decode payload")
    let body = try #require(bodyBox.get(), "Body should be captured")
    let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
    let encodedDate = (json?["date"] as? Double) ?? (json?["date"] as? NSNumber)?.doubleValue
    #expect(encodedDate == 0.0, "Custom encoder should encode date as seconds since 1970")
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
