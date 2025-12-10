//
//  NetworkManagerTests.swift
//  EKNetworkTests
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Testing
import Foundation
@testable import EKNetwork

@Suite("NetworkManager Tests")
struct NetworkManagerTestSuite {
}

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

@MainActor
@Test("query parameters are correctly appended to URL")
func testQueryParameters() async throws {
    final class URLBox: @unchecked Sendable {
        private var url: URL? = nil
        func set(_ new: URL?) { url = new }
        func get() -> URL? { url }
    }
    let urlBox = URLBox()
    
    struct QueryRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/search" }
        var method: HTTPMethod { .get }
        var queryParameters: [String: String]? {
            ["q": "test", "page": "1"]
        }
    }
    
    class QueryProtocol: URLProtocol {
        nonisolated(unsafe) static var urlBox: URLBox?
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "result"))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.urlBox?.set(request.url)
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [QueryProtocol.self]
    QueryProtocol.urlBox = urlBox
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    _ = try await manager.send(QueryRequest(), accessToken: nil)
    
    let url = try #require(urlBox.get())
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []
    #expect(queryItems.count == 2, "Should have 2 query parameters")
    #expect(queryItems.contains { $0.name == "q" && $0.value == "test" }, "Should contain q=test")
    #expect(queryItems.contains { $0.name == "page" && $0.value == "1" }, "Should contain page=1")
}

@MainActor
@Test("form URL encoded body is correctly encoded")
func testFormURLEncodedBody() async throws {
    final class BodyBox: @unchecked Sendable {
        private var data: Data?
        private var contentType: String?
        func setBody(_ new: Data?) { data = new }
        func setContentType(_ new: String?) { contentType = new }
        func getBody() -> Data? { data }
        func getContentType() -> String? { contentType }
    }
    let bodyBox = BodyBox()
    
    struct FormRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/form" }
        var method: HTTPMethod { .post }
        var body: RequestBody? {
            RequestBody(formURLEncoded: ["name": "John", "email": "john@example.com"])
        }
    }
    
    // Use mock URLSessionProtocol to capture body properly
    class MockSession: URLSessionProtocol {
        let bodyBox: BodyBox
        init(bodyBox: BodyBox) {
            self.bodyBox = bodyBox
        }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            bodyBox.setBody(request.httpBody)
            bodyBox.setContentType(request.value(forHTTPHeaderField: "Content-Type"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONEncoder().encode(MockResponse(value: "success"))
            return (data, response)
        }
    }
    
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: MockSession(bodyBox: bodyBox))
    _ = try await manager.send(FormRequest(), accessToken: nil)
    
    let contentType = try #require(bodyBox.getContentType())
    #expect(contentType == "application/x-www-form-urlencoded", "Should have correct Content-Type")
    
    let body = try #require(bodyBox.getBody())
    let bodyString = String(data: body, encoding: .utf8) ?? ""
    #expect(bodyString.contains("name=John"), "Should contain name=John")
    // URLComponents may encode @ differently, check for either encoded or unencoded version
    #expect(bodyString.contains("email=john%40example.com") || bodyString.contains("email=john@example.com"), "Should contain email parameter")
}

@MainActor
@Test("multipart form data is correctly encoded")
func testMultipartFormData() async throws {
    final class BodyBox: @unchecked Sendable {
        private var data: Data?
        private var contentType: String?
        func setBody(_ new: Data?) { data = new }
        func setContentType(_ new: String?) { contentType = new }
        func getBody() -> Data? { data }
        func getContentType() -> String? { contentType }
    }
    let bodyBox = BodyBox()
    
    struct MultipartRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/upload" }
        var method: HTTPMethod { .post }
        var multipartData: MultipartFormData? {
            var data = MultipartFormData()
            data.addPart(name: "file", data: "test content".data(using: .utf8)!, mimeType: "text/plain", filename: "test.txt")
            data.addPart(name: "description", data: "Test file".data(using: .utf8)!, mimeType: "text/plain")
            return data
        }
    }
    
    // Use mock URLSessionProtocol to capture body properly
    class MockSession: URLSessionProtocol {
        let bodyBox: BodyBox
        init(bodyBox: BodyBox) {
            self.bodyBox = bodyBox
        }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            bodyBox.setBody(request.httpBody)
            bodyBox.setContentType(request.value(forHTTPHeaderField: "Content-Type"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONEncoder().encode(MockResponse(value: "uploaded"))
            return (data, response)
        }
    }
    
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: MockSession(bodyBox: bodyBox))
    _ = try await manager.send(MultipartRequest(), accessToken: nil)
    
    let contentType = try #require(bodyBox.getContentType())
    #expect(contentType.hasPrefix("multipart/form-data"), "Should have multipart Content-Type")
    #expect(contentType.contains("boundary="), "Should contain boundary")
    
    let body = try #require(bodyBox.getBody())
    let bodyString = String(data: body, encoding: .utf8) ?? ""
    #expect(bodyString.contains("Content-Disposition: form-data"), "Should contain form-data disposition")
    #expect(bodyString.contains("name=\"file\""), "Should contain file field")
    #expect(bodyString.contains("filename=\"test.txt\""), "Should contain filename")
    #expect(bodyString.contains("test content"), "Should contain file content")
}

@MainActor
@Test("conflicting body and multipartData throws error")
func testConflictingBodyTypes() async throws {
    struct ConflictingRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/conflict" }
        var method: HTTPMethod { .post }
        var body: RequestBody? {
            RequestBody(encodable: ["test": "data"])
        }
        var multipartData: MultipartFormData? {
            var data = MultipartFormData()
            data.addPart(name: "file", data: Data(), mimeType: "application/octet-stream")
            return data
        }
    }
    
    class ErrorProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            // Should not reach here
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ErrorProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    do {
        _ = try await manager.send(ConflictingRequest(), accessToken: nil)
        Issue.record("Should have thrown NetworkError.conflictingBodyTypes")
    } catch NetworkError.conflictingBodyTypes {
        // Expected
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@MainActor
@Test("HTTP error is thrown for non-2xx status codes")
func testHTTPErrorHandling() async throws {
    struct ErrorRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/error" }
        var method: HTTPMethod { .get }
    }
    
    class ErrorProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let errorData = "Error message".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: ["X-Custom": "value"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: errorData)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ErrorProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    do {
        _ = try await manager.send(ErrorRequest(), accessToken: nil)
        Issue.record("Should have thrown HTTPError")
    } catch let error as HTTPError {
        #expect(error.statusCode == 404, "Should have 404 status code")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@MainActor
@Test("custom error decoder is used when provided")
func testCustomErrorDecoder() async throws {
    struct CustomError: Error, Equatable {
        let message: String
    }
    
    struct ErrorRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/error" }
        var method: HTTPMethod { .get }
        var errorDecoder: ((Data) -> Error?)? {
            { data in
                if let message = String(data: data, encoding: .utf8) {
                    return CustomError(message: message)
                }
                return nil
            }
        }
    }
    
    class ErrorProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let errorData = "Custom error message".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: errorData)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ErrorProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    do {
        _ = try await manager.send(ErrorRequest(), accessToken: nil)
        Issue.record("Should have thrown an error")
    } catch let error as CustomError {
        #expect(error.message == "Custom error message", "Should decode custom error")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@MainActor
@Test("retry policy retries on transient errors")
func testRetryPolicy() async throws {
    struct RetryRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/retry" }
        var method: HTTPMethod { .get }
        var retryPolicy: RetryPolicy {
            RetryPolicy(maxRetryCount: 2, delay: 0.01) { error in
                if let urlError = error as? URLError {
                    return urlError.code == .timedOut
                }
                return false
            }
        }
    }
    
    class RetryProtocol: URLProtocol {
        nonisolated(unsafe) static var attemptCount: UnsafeMutablePointer<Int>?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.attemptCount?.pointee += 1
            let currentAttempt = Self.attemptCount?.pointee ?? 0
            
            if currentAttempt < 3 {
                // Simulate timeout error
                let error = URLError(.timedOut)
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                // Success on third attempt
                guard let url = request.url else { return }
                let data = try! JSONEncoder().encode(MockResponse(value: "success"))
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RetryProtocol.self]
    RetryProtocol.attemptCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    RetryProtocol.attemptCount?.initialize(to: 0)
    defer { RetryProtocol.attemptCount?.deallocate() }
    
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    let result = try await manager.send(RetryRequest(), accessToken: nil)
    
    #expect(result.value == "success", "Should succeed after retries")
    #expect(RetryProtocol.attemptCount?.pointee == 3, "Should have retried 2 times (3 total attempts)")
}

@MainActor
@Test("401 triggers token refresh when allowsRetry is true")
func testTokenRefresh() async throws {
    class MockTokenRefresher: TokenRefreshProvider {
        var refreshCalled = false
        func refreshTokenIfNeeded() async throws {
            refreshCalled = true
        }
    }
    
    struct AuthRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/auth" }
        var method: HTTPMethod { .get }
        var allowsRetry: Bool { true }
    }
    
    class AuthProtocol: URLProtocol {
        nonisolated(unsafe) static var requestCount: UnsafeMutablePointer<Int>?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requestCount?.pointee += 1
            let currentRequest = Self.requestCount?.pointee ?? 0
            
            guard let url = request.url else { return }
            
            if currentRequest == 1 {
                // First request returns 401
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                // Second request succeeds
                let data = try! JSONEncoder().encode(MockResponse(value: "success"))
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthProtocol.self]
    AuthProtocol.requestCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    AuthProtocol.requestCount?.initialize(to: 0)
    defer { AuthProtocol.requestCount?.deallocate() }
    
    let refresher = MockTokenRefresher()
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    manager.tokenRefresher = refresher
    
    let result = try await manager.send(AuthRequest(), accessToken: nil)
    
    #expect(refresher.refreshCalled, "Token refresher should be called")
    #expect(result.value == "success", "Should succeed after token refresh")
    #expect(AuthProtocol.requestCount?.pointee == 2, "Should have made 2 requests")
}

@MainActor
@Test("401 throws error when allowsRetry is false")
func testUnauthorizedWithoutRetry() async throws {
    struct AuthRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/auth" }
        var method: HTTPMethod { .get }
        var allowsRetry: Bool { false }
    }
    
    class AuthProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    do {
        _ = try await manager.send(AuthRequest(), accessToken: nil)
        Issue.record("Should have thrown NetworkError.unauthorized")
    } catch NetworkError.unauthorized {
        // Expected
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@MainActor
@Test("User-Agent header is set when configuration is provided")
func testUserAgentConfiguration() async throws {
    final class HeaderBox: @unchecked Sendable {
        private var userAgent: String?
        func set(_ new: String?) { userAgent = new }
        func get() -> String? { userAgent }
    }
    let headerBox = HeaderBox()
    
    struct UserAgentRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/test" }
        var method: HTTPMethod { .get }
    }
    
    class UserAgentProtocol: URLProtocol {
        nonisolated(unsafe) static var headerBox: HeaderBox?
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "result"))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.headerBox?.set(request.value(forHTTPHeaderField: "User-Agent"))
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UserAgentProtocol.self]
    UserAgentProtocol.headerBox = headerBox
    
    let userAgentConfig = UserAgentConfiguration(
        appName: "TestApp",
        appVersion: "1.0.0",
        bundleIdentifier: "com.test.app",
        buildNumber: "100",
        osVersion: "14.0"
    )
    let manager = NetworkManager(
        baseURL: URL(string: "https://api.test")!,
        session: URLSession(configuration: config),
        userAgentConfiguration: userAgentConfig
    )
    
    _ = try await manager.send(UserAgentRequest(), accessToken: nil)
    
    let userAgent = try #require(headerBox.get())
    #expect(userAgent.contains("TestApp/1.0.0"), "Should contain app name and version")
    #expect(userAgent.contains("com.test.app"), "Should contain bundle identifier")
    #expect(userAgent.contains("EKNetwork/"), "Should contain EKNetwork version")
}

@MainActor
@Test("accessToken closure adds Bearer token to Authorization header")
func testAccessTokenInjection() async throws {
    final class HeaderBox: @unchecked Sendable {
        private var auth: String?
        func set(_ new: String?) { auth = new }
        func get() -> String? { auth }
    }
    let headerBox = HeaderBox()
    
    struct TokenRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/test" }
        var method: HTTPMethod { .get }
    }
    
    class TokenProtocol: URLProtocol {
        nonisolated(unsafe) static var headerBox: HeaderBox?
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "result"))
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
    config.protocolClasses = [TokenProtocol.self]
    TokenProtocol.headerBox = headerBox
    
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    let tokenProvider: @Sendable () -> String? = { "test-token-123" }
    
    _ = try await manager.send(TokenRequest(), accessToken: tokenProvider)
    
    let auth = try #require(headerBox.get())
    #expect(auth == "Bearer test-token-123", "Should add Bearer prefix to token")
}

@MainActor
@Test("different HTTP methods are correctly set")
func testHTTPMethods() async throws {
    final class MethodBox: @unchecked Sendable {
        private var method: String?
        func set(_ new: String?) { method = new }
        func get() -> String? { method }
    }
    
    nonisolated func testMethod(_ httpMethod: HTTPMethod, expectedMethod: String) async throws {
        let methodBox = MethodBox()
        
        struct MethodRequest: NetworkRequest {
            typealias Response = MockResponse
            var path: String { "/test" }
            let method: HTTPMethod
        }
        
        class MethodProtocol: URLProtocol {
            nonisolated(unsafe) static var methodBox: MethodBox?
            static let data: Data = {
                try! JSONEncoder().encode(MockResponse(value: "result"))
            }()
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Self.methodBox?.set(request.httpMethod)
                guard let url = request.url else { return }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Self.data)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MethodProtocol.self]
        MethodProtocol.methodBox = methodBox
        
        let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
        let request = MethodRequest(method: httpMethod)
        _ = try await manager.send(request, accessToken: nil)
        
        let method = try #require(methodBox.get())
        #expect(method == expectedMethod, "Should use \(expectedMethod) method")
    }
    
    try await testMethod(.get, expectedMethod: "GET")
    try await testMethod(.post, expectedMethod: "POST")
    try await testMethod(.put, expectedMethod: "PUT")
    try await testMethod(.delete, expectedMethod: "DELETE")
    try await testMethod(.patch, expectedMethod: "PATCH")
}

@MainActor
@Test("raw data body is correctly set")
func testRawDataBody() async throws {
    final class BodyBox: @unchecked Sendable {
        private var data: Data?
        private var contentType: String?
        func setBody(_ new: Data?) { data = new }
        func setContentType(_ new: String?) { contentType = new }
        func getBody() -> Data? { data }
        func getContentType() -> String? { contentType }
    }
    let bodyBox = BodyBox()
    
    struct RawDataRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/raw" }
        var method: HTTPMethod { .post }
        var body: RequestBody? {
            RequestBody(data: "raw data".data(using: .utf8)!, contentType: "application/octet-stream")
        }
    }
    
    // Use mock URLSessionProtocol to capture body properly
    class MockSession: URLSessionProtocol {
        let bodyBox: BodyBox
        init(bodyBox: BodyBox) {
            self.bodyBox = bodyBox
        }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            bodyBox.setBody(request.httpBody)
            bodyBox.setContentType(request.value(forHTTPHeaderField: "Content-Type"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONEncoder().encode(MockResponse(value: "success"))
            return (data, response)
        }
    }
    
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: MockSession(bodyBox: bodyBox))
    _ = try await manager.send(RawDataRequest(), accessToken: nil)
    
    let contentType = try #require(bodyBox.getContentType())
    #expect(contentType == "application/octet-stream", "Should have correct Content-Type")
    
    let body = try #require(bodyBox.getBody())
    let bodyString = String(data: body, encoding: .utf8) ?? ""
    #expect(bodyString == "raw data", "Should contain raw data")
}

@MainActor
@Test("Content-Length header is set for known body sizes")
func testContentLengthHeader() async throws {
    final class HeaderBox: @unchecked Sendable {
        private var contentLength: String?
        func set(_ new: String?) { contentLength = new }
        func get() -> String? { contentLength }
    }
    let headerBox = HeaderBox()
    
    struct LengthRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/length" }
        var method: HTTPMethod { .post }
        var body: RequestBody? {
            RequestBody(encodable: ["test": "data"])
        }
    }
    
    class LengthProtocol: URLProtocol {
        nonisolated(unsafe) static var headerBox: HeaderBox?
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "success"))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.headerBox?.set(request.value(forHTTPHeaderField: "Content-Length"))
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LengthProtocol.self]
    LengthProtocol.headerBox = headerBox
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    _ = try await manager.send(LengthRequest(), accessToken: nil)
    
    let contentLength = try #require(headerBox.get())
    let length = Int(contentLength) ?? 0
    #expect(length > 0, "Content-Length should be set and greater than 0")
}
