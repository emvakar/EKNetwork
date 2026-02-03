//
//  ExtendedTestSuite.swift
//  EKNetworkTests
//
//  Created by Emil Karimov on 03.02.2026.
//  Copyright © 2026 Emil Karimov. All rights reserved.
//

import Testing
import Foundation
@testable import EKNetwork

@Suite("Extended Test Suite")
struct ExtendedTestSuite {}

private struct ExtendedMockResponse: Codable, Equatable {
    let value: String
}

// MARK: - HTTPMethod

@Test("HTTPMethod get raw value")
func testHTTPMethodGet() {
    #expect(HTTPMethod.get.rawValue == "GET")
}

@Test("HTTPMethod post raw value")
func testHTTPMethodPost() {
    #expect(HTTPMethod.post.rawValue == "POST")
}

@Test("HTTPMethod put raw value")
func testHTTPMethodPut() {
    #expect(HTTPMethod.put.rawValue == "PUT")
}

@Test("HTTPMethod delete raw value")
func testHTTPMethodDelete() {
    #expect(HTTPMethod.delete.rawValue == "DELETE")
}

@Test("HTTPMethod patch raw value")
func testHTTPMethodPatch() {
    #expect(HTTPMethod.patch.rawValue == "PATCH")
}

// MARK: - NetworkError

@Test("NetworkError invalidURL case")
func testNetworkErrorInvalidURL() {
    let error = NetworkError.invalidURL
    if case .invalidURL = error {} else { Issue.record("Expected invalidURL") }
}

@Test("NetworkError invalidMultipartEncoding case")
func testNetworkErrorInvalidMultipartEncoding() {
    if case .invalidMultipartEncoding = NetworkError.invalidMultipartEncoding {} else { Issue.record("Expected invalidMultipartEncoding") }
}

@Test("NetworkError emptyResponse case")
func testNetworkErrorEmptyResponse() {
    if case .emptyResponse = NetworkError.emptyResponse {} else { Issue.record("Expected emptyResponse") }
}

@Test("NetworkError unauthorized case")
func testNetworkErrorUnauthorized() {
    if case .unauthorized = NetworkError.unauthorized {} else { Issue.record("Expected unauthorized") }
}

@Test("NetworkError conflictingBodyTypes case")
func testNetworkErrorConflictingBodyTypes() {
    if case .conflictingBodyTypes = NetworkError.conflictingBodyTypes {} else { Issue.record("Expected conflictingBodyTypes") }
}

// MARK: - RequestBody

@Test("RequestBody encodable init")
func testRequestBodyEncodableInit() {
    let body = RequestBody(encodable: ExtendedMockResponse(value: "x"), contentType: "application/json")
    #expect(body.contentType == "application/json")
}

@Test("RequestBody raw data init")
func testRequestBodyRawInit() {
    let data = Data("hello".utf8)
    let body = RequestBody(data: data, contentType: "text/plain")
    #expect(body.contentType == "text/plain")
}

@Test("RequestBody formURLEncoded init")
func testRequestBodyFormURLEncodedInit() {
    let body = RequestBody(formURLEncoded: ["a": "1", "b": "2"])
    #expect(body.contentType == "application/x-www-form-urlencoded")
}

@Test("RetryPolicy init with defaults")
func testRetryPolicyInitDefaults() {
    let policy = RetryPolicy()
    #expect(policy.maxRetryCount == 0)
    #expect(policy.delay == 1.0)
}

@Test("RetryPolicy init with custom values")
func testRetryPolicyInitCustom() {
    let policy = RetryPolicy(maxRetryCount: 5, delay: 2.0) { _ in false }
    #expect(policy.maxRetryCount == 5)
    #expect(policy.delay == 2.0)
    #expect(policy.shouldRetry(URLError(.unknown)) == false)
}

// MARK: - MultipartFormData Part

@Test("MultipartFormData Part init")
func testMultipartFormDataPartInit() {
    let part = MultipartFormData.Part(name: "file", filename: "a.txt", data: Data(), mimeType: "text/plain")
    #expect(part.name == "file")
    #expect(part.filename == "a.txt")
    #expect(part.mimeType == "text/plain")
}

@Test("MultipartFormData Part without filename")
func testMultipartFormDataPartNoFilename() {
    let part = MultipartFormData.Part(name: "field", data: Data("v".utf8), mimeType: "text/plain")
    #expect(part.filename == nil)
}

@Test("MultipartFormData empty encodedData")
func testMultipartFormDataEmptyEncoded() async throws {
    let multipart = MultipartFormData()
    let data = try #require(multipart.encodedData(), "Empty multipart should encode")
    #expect(!data.isEmpty)
    let str = String(data: data, encoding: .utf8) ?? ""
    #expect(str.contains(multipart.boundary))
}

@Test("MultipartFormData boundary is unique")
func testMultipartFormDataBoundaryUnique() {
    let m1 = MultipartFormData()
    let m2 = MultipartFormData()
    #expect(m1.boundary != m2.boundary)
}

@Test("StatusCodeResponse Equatable")
func testStatusCodeResponseEquatable() {
    let a = StatusCodeResponse(statusCode: 200, headers: ["X": "1"])
    let b = StatusCodeResponse(statusCode: 200, headers: ["X": "1"])
    #expect(a == b)
}

// MARK: - EmptyResponse / HTTPError

@Test("EmptyResponse init and Equatable")
func testEmptyResponseInit() {
    let a = EmptyResponse()
    let b = EmptyResponse()
    #expect(a == b)
}

@Test("HTTPError errorDescription")
func testHTTPErrorErrorDescription() {
    let error = HTTPError(statusCode: 404, data: Data(), headers: [:])
    #expect(error.errorDescription?.contains("404") == true)
}

@Test("HTTPError init with headers")
func testHTTPErrorInitHeaders() {
    let error = HTTPError(statusCode: 500, data: Data(), headers: ["X-Custom": "value"])
    #expect(error.statusCode == 500)
    #expect(error.headers["X-Custom"] == "value")
}

@Test("UserAgentConfiguration explicit values")
func testUserAgentConfigurationExplicit() {
    let config = UserAgentConfiguration(
        appName: "Test",
        appVersion: "2.0",
        bundleIdentifier: "com.test",
        buildNumber: "100",
        osVersion: "18.0",
        networkVersion: "1.0"
    )
    let ua = config.generateUserAgentString()
    #expect(ua.contains("Test/2.0"))
    #expect(ua.contains("com.test"))
    #expect(ua.contains("EKNetwork/1.0"))
}

@Test("UserAgentConfiguration platform in string")
func testUserAgentConfigurationPlatform() {
    let config = UserAgentConfiguration(appName: "A", appVersion: "1", bundleIdentifier: "b", buildNumber: "1", osVersion: "18", networkVersion: "1")
    let ua = config.generateUserAgentString()
    #expect(ua.contains("EKNetwork/1"))
}

// MARK: - Integration-style

@Test("NetworkManager baseURL closure called")
func testNetworkManagerBaseURLClosureCalled() {
    var callCount = 0
    let url = URL(string: "https://base.test")!
    let manager = NetworkManager(baseURL: {
        callCount += 1
        return url
    })
    _ = manager.baseURL()
    _ = manager.baseURL()
    #expect(callCount == 2)
}

@Test("NetworkManager tokenRefresher is writable")
func testNetworkManagerTokenRefresherWritable() {
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! })
    #expect(manager.tokenRefresher == nil)
    class MockRefresher: TokenRefreshProvider {
        func refreshTokenIfNeeded() async throws {}
    }
    let ref = MockRefresher()
    manager.tokenRefresher = ref
    #expect(manager.tokenRefresher !== nil)
}

@Test("NetworkManager userAgentConfiguration is writable")
func testNetworkManagerUserAgentWritable() {
    let manager = NetworkManager(baseURL: { URL(string: "https://api.test")! })
    #expect(manager.userAgentConfiguration == nil)
    let config = UserAgentConfiguration(appName: "T", appVersion: "1", bundleIdentifier: "b", buildNumber: "1", osVersion: "18", networkVersion: "1")
    manager.userAgentConfiguration = config
    #expect(manager.userAgentConfiguration != nil)
}

@Test("URLSession conforms to URLSessionProtocol")
func testURLSessionConformsToProtocol() {
    let session = URLSession.shared
    let _: URLSessionProtocol = session
}

@MainActor
@Test("NetworkProgress fractionCompleted initial")
func testNetworkProgressInitial() async {
    let progress = NetworkProgress()
    #expect(progress.fractionCompleted == 0.0)
}
