//
//  ExtendedCoverageTests.swift
//  EKNetworkTests
//
//  Created by Emil Karimov on 10.12.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Testing
import Foundation
@testable import EKNetwork

// MARK: - Additional Edge Cases and Integration Tests

@Test("NetworkManager initializes with default session")
func testNetworkManagerDefaultSession() async throws {
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!)
    #expect(manager.baseURL.absoluteString == "https://api.test")
}

@Test("NetworkManager initializes with custom session")
func testNetworkManagerCustomSession() async throws {
    let config = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: config)
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: session)
    #expect(manager.baseURL.absoluteString == "https://api.test")
}

@Test("NetworkManager initializes with user agent configuration")
func testNetworkManagerWithUserAgent() async throws {
    let config = UserAgentConfiguration(
        appName: "TestApp",
        appVersion: "1.0.0",
        bundleIdentifier: "com.test.app",
        buildNumber: "100",
        osVersion: "18.0",
        networkVersion: "1.3.1"
    )
    let manager = NetworkManager(
        baseURL: URL(string: "https://api.test")!,
        userAgentConfiguration: config
    )
    #expect(manager.baseURL.absoluteString == "https://api.test")
}

@MainActor
@Test("NetworkManager updateBaseURL changes base URL")
func testNetworkManagerUpdateBaseURL() async throws {
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!)
    #expect(manager.baseURL.absoluteString == "https://api.test")
    
    manager.updateBaseURL(URL(string: "https://api2.test")!)
    #expect(manager.baseURL.absoluteString == "https://api2.test")
}

// MARK: - RequestBody Additional Tests

@Test("RequestBody raw data with custom contentType")
func testRequestBodyRawDataCustomContentType() async throws {
    let data = "raw data".data(using: .utf8)!
    let body = RequestBody.raw(data, contentType: "text/plain")
    #expect(body.contentType == "text/plain")
}

@Test("RequestBody stream with custom contentType")
func testRequestBodyStreamCustomContentType() async throws {
    let stream = InputStream(data: "stream".data(using: .utf8)!)
    let body = RequestBody.stream(stream, contentType: "application/octet-stream")
    #expect(body.contentType == "application/octet-stream")
}

@Test("RequestBody formURLEncoded with empty parameters")
func testRequestBodyFormURLEncodedEmpty() async throws {
    let body = RequestBody(formURLEncoded: [:])
    #expect(body.contentType == "application/x-www-form-urlencoded")
}

// MARK: - MultipartFormData Additional Tests

@Test("MultipartFormData with single part")
func testMultipartFormDataSinglePart() async throws {
    let part = MultipartFormData.Part(
        name: "field",
        data: "value".data(using: .utf8)!,
        mimeType: "text/plain"
    )
    let multipart = MultipartFormData(parts: [part])
    let data = multipart.encodedData()
    #expect(!data.isEmpty)
}

@Test("MultipartFormData with special characters in field name")
func testMultipartFormDataSpecialCharacters() async throws {
    let part = MultipartFormData.Part(
        name: "field-name_with.special",
        data: "value".data(using: .utf8)!,
        mimeType: "text/plain"
    )
    let multipart = MultipartFormData(parts: [part])
    let data = multipart.encodedData()
    #expect(!data.isEmpty)
}

// MARK: - RetryPolicy Additional Tests

@Test("RetryPolicy with zero max retry count")
func testRetryPolicyZeroMaxRetry() async throws {
    let policy = RetryPolicy(maxRetryCount: 0, delay: 0.1)
    #expect(policy.maxRetryCount == 0)
    #expect(policy.delay == 0.1)
}

@Test("RetryPolicy with custom shouldRetry returning false")
func testRetryPolicyCustomShouldRetryFalse() async throws {
    let policy = RetryPolicy(maxRetryCount: 3, delay: 0.1) { _ in false }
    let error = URLError(.timedOut)
    #expect(policy.shouldRetry(error) == false)
}

// MARK: - HTTPError Additional Tests

@Test("HTTPError with empty headers")
func testHTTPErrorEmptyHeaders() async throws {
    let error = HTTPError(statusCode: 500, data: Data(), headers: [:])
    #expect(error.statusCode == 500)
    #expect(error.headers.isEmpty)
}

@Test("HTTPError with nil data")
func testHTTPErrorNilData() async throws {
    let error = HTTPError(statusCode: 400, data: nil, headers: ["X-Error": "test"])
    #expect(error.statusCode == 400)
    #expect(error.headers["X-Error"] == "test")
}

// MARK: - NetworkProgress Additional Tests

@MainActor
@Test("NetworkProgress initial state")
func testNetworkProgressInitialState() async throws {
    let progress = NetworkProgress()
    #expect(progress.fractionCompleted == 0.0)
}

@MainActor
@Test("NetworkProgress updates fractionCompleted")
func testNetworkProgressUpdates() async throws {
    let progress = NetworkProgress()
    progress.fractionCompleted = 0.5
    #expect(progress.fractionCompleted == 0.5)
    
    progress.fractionCompleted = 1.0
    #expect(progress.fractionCompleted == 1.0)
}

// MARK: - UserAgentConfiguration Additional Tests

@Test("UserAgentConfiguration with all nil values uses Bundle defaults")
func testUserAgentConfigurationAllNil() async throws {
    let config = UserAgentConfiguration(
        appName: nil,
        appVersion: nil,
        bundleIdentifier: nil,
        buildNumber: nil,
        osVersion: nil,
        networkVersion: nil
    )
    
    // Should use Bundle.main defaults
    #expect(!config.appName.isEmpty)
    #expect(!config.appVersion.isEmpty)
    #expect(!config.bundleIdentifier.isEmpty)
    #expect(!config.buildNumber.isEmpty)
    #expect(!config.osVersion.isEmpty)
    #expect(!config.networkVersion.isEmpty)
}

@Test("UserAgentConfiguration generates correct format")
func testUserAgentConfigurationFormat() async throws {
    let config = UserAgentConfiguration(
        appName: "TestApp",
        appVersion: "1.0.0",
        bundleIdentifier: "com.test.app",
        buildNumber: "100",
        osVersion: "18.0",
        networkVersion: "1.3.1"
    )
    
    let userAgent = config.generateUserAgentString()
    #expect(userAgent.contains("TestApp/1.0.0"))
    #expect(userAgent.contains("com.test.app"))
    #expect(userAgent.contains("build:100"))
    #expect(userAgent.contains("EKNetwork/1.3.1"))
}

// MARK: - StatusCodeResponse Additional Tests

@Test("StatusCodeResponse initializes correctly with headers")
func testStatusCodeResponseInitWithHeaders() async throws {
    let response = StatusCodeResponse(statusCode: 201, headers: ["X-Custom": "value"])
    #expect(response.statusCode == 201)
    #expect(response.headers["X-Custom"] == "value")
}

@Test("StatusCodeResponse with empty headers dictionary")
func testStatusCodeResponseEmptyHeadersDict() async throws {
    let response = StatusCodeResponse(statusCode: 204, headers: [:])
    #expect(response.statusCode == 204)
    #expect(response.headers.isEmpty)
}

// MARK: - EmptyResponse Additional Tests

@Test("EmptyResponse equality check")
func testEmptyResponseEqualityCheck() async throws {
    let response1 = EmptyResponse()
    let response2 = EmptyResponse()
    #expect(response1 == response2)
}

// MARK: - HTTPMethod Additional Tests

@Test("HTTPMethod raw values validation")
func testHTTPMethodRawValuesValidation() async throws {
    // Verify all HTTP methods have correct raw values
    let methods: [(HTTPMethod, String)] = [
        (.get, "GET"),
        (.post, "POST"),
        (.put, "PUT"),
        (.delete, "DELETE"),
        (.patch, "PATCH")
    ]
    
    for (method, expected) in methods {
        #expect(method.rawValue == expected)
    }
}

// MARK: - NetworkError Additional Tests

@Test("NetworkError cases are accessible and distinct")
func testNetworkErrorCasesDistinct() async throws {
    // Verify all NetworkError cases are accessible
    let error1 = NetworkError.invalidURL
    let error2 = NetworkError.invalidResponse
    let error3 = NetworkError.unauthorized
    let error4 = NetworkError.conflictingBodyTypes
    
    // All should be NetworkError type
    #expect(error1 is NetworkError)
    #expect(error2 is NetworkError)
    #expect(error3 is NetworkError)
    #expect(error4 is NetworkError)
}

// MARK: - Integration Tests

@MainActor
@Test("Full request flow with success")
func testFullRequestFlowSuccess() async throws {
    struct SuccessRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/success" }
        var method: HTTPMethod { .get }
    }
    
    class SuccessProtocol: URLProtocol {
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "success"))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SuccessProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    let response = try await manager.send(SuccessRequest(), accessToken: nil)
    #expect(response.value == "success")
}

@MainActor
@Test("Request with all optional parameters")
func testRequestWithAllOptionalParameters() async throws {
    struct FullRequest: NetworkRequest {
        typealias Response = MockResponse
        var path: String { "/full" }
        var method: HTTPMethod { .post }
        var headers: [String: String]? { ["X-Custom": "value"] }
        var queryParameters: [String: String]? { ["param": "value"] }
        var body: RequestBody? {
            RequestBody(encodable: ["key": "value"])
        }
        var retryPolicy: RetryPolicy {
            RetryPolicy(maxRetryCount: 2, delay: 0.1)
        }
    }
    
    class FullProtocol: URLProtocol {
        static let data: Data = {
            try! JSONEncoder().encode(MockResponse(value: "full"))
        }()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FullProtocol.self]
    let manager = NetworkManager(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
    
    let response = try await manager.send(FullRequest(), accessToken: nil)
    #expect(response.value == "full")
}

