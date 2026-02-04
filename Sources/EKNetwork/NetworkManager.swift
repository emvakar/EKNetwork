//
//  NetworkManager.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.12.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import os
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif


/// Configuration for User-Agent header generation.
/// Formats the User-Agent string as: `AppName/Version (BundleID; build:BuildNumber; iOS Version) EKNetwork/Version`
public struct UserAgentConfiguration {
    /// Application name (e.g., "Cashdesk").
    public let appName: String
    /// Application version (e.g., "2.2.0").
    public let appVersion: String
    /// Bundle identifier (e.g., "com.taxcom.cashdesk").
    public let bundleIdentifier: String
    /// Build number (e.g., "116").
    public let buildNumber: String
    /// iOS/OS version (e.g., "17.3.1").
    public let osVersion: String
    /// EKNetwork framework version (defaults to embedded version file, which matches the connected SPM package version).
    public let networkVersion: String
    
    /// Initializes a User-Agent configuration.
    /// - Parameters:
    ///   - appName: Application name. Defaults to CFBundleName from Bundle.main.
    ///   - appVersion: Application version. Defaults to CFBundleShortVersionString from Bundle.main.
    ///   - bundleIdentifier: Bundle identifier. Defaults to CFBundleIdentifier from Bundle.main.
    ///   - buildNumber: Build number. Defaults to CFBundleVersion from Bundle.main.
    ///   - osVersion: OS version. Defaults to current system version.
    ///   - networkVersion: EKNetwork version. Defaults to embedded version file (Version.swift), which always matches the connected SPM package version.
    public init(
        appName: String? = nil,
        appVersion: String? = nil,
        bundleIdentifier: String? = nil,
        buildNumber: String? = nil,
        osVersion: String? = nil,
        networkVersion: String? = nil
    ) {
        let mainBundle = Bundle.main
        
        self.appName = appName ?? mainBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
        self.appVersion = appVersion ?? mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        self.bundleIdentifier = bundleIdentifier ?? mainBundle.bundleIdentifier ?? "com.unknown.app"
        self.buildNumber = buildNumber ?? mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        // Get OS version
        let defaultOSVersion: String
        #if canImport(UIKit)
        // UIDevice.current.systemVersion is safe to use synchronously in initialization
        defaultOSVersion = UIDevice.current.systemVersion
        #elseif canImport(AppKit)
        let systemOSVersion = ProcessInfo.processInfo.operatingSystemVersion
        defaultOSVersion = "\(systemOSVersion.majorVersion).\(systemOSVersion.minorVersion).\(systemOSVersion.patchVersion)"
        #else
        defaultOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif
        
        self.osVersion = osVersion ?? defaultOSVersion
        
        // Get EKNetwork version from git tag (with fallback to Bundle)
        // Priority: 1) provided networkVersion, 2) environment variable EKNETWORK_VERSION, 3) git tag, 4) Bundle
        self.networkVersion = networkVersion ?? EKNetworkVersion.current
    }
    
    /// Generates the User-Agent string in the format:
    /// `AppName/Version (BundleID; build:BuildNumber; iOS/iOSVersion) EKNetwork/Version`
    public func generateUserAgentString() -> String {
        let platform: String
        #if canImport(UIKit)
        platform = "iOS"
        #elseif canImport(AppKit)
        platform = "macOS"
        #else
        platform = "Unknown"
        #endif
        
        return "\(appName)/\(appVersion) (\(bundleIdentifier); build:\(buildNumber); \(platform) \(osVersion)) EKNetwork/\(networkVersion)"
    }
}

/// Normalizes request path: trims slashes, collapses "//", and rejects ".." (path traversal).
/// - Returns: Normalized path (e.g. "/users" or "/"), or nil if path is invalid (e.g. contains "..").
private func normalizePath(_ path: String) -> String? {
    var p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    while p.contains("//") { p = p.replacingOccurrences(of: "//", with: "/") }
    if p.contains("..") { return nil }
    return p.isEmpty ? "/" : "/" + p
}

private func normalizeHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
    headers.reduce(into: [String: String]()) { result, element in
        guard let key = element.key as? String else { return }
        if let value = element.value as? String {
            result[key] = value
        } else {
            result[key] = String(describing: element.value)
        }
    }
}

/// HTTP methods supported by the network layer.
public enum HTTPMethod: String {

    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"

}

/// Escapes double quotes and backslashes in Content-Disposition header values (name, filename).
private func escapeMultipartHeaderValue(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

/// Encodes a string to UTF-8 Data; returns nil if encoding fails (avoids force unwrap).
private func utf8Data(_ string: String) -> Data? {
    string.data(using: .utf8)
}

/// Represents multipart form data for file uploads.
public struct MultipartFormData {

    /// Represents a single part in the multipart form data.
    public struct Part {
        /// Name of the form field.
        public let name: String
        /// Optional filename for the part.
        public let filename: String?
        /// Data content of the part.
        public let data: Data
        /// MIME type of the data.
        public let mimeType: String
        
        /// Initializes a new multipart form data part.
        /// - Parameters:
        ///   - name: Form field name.
        ///   - filename: Optional filename.
        ///   - data: Data content.
        ///   - mimeType: MIME type string.
        public init(name: String, filename: String? = nil, data: Data, mimeType: String) {
            self.name = name
            self.filename = filename
            self.data = data
            self.mimeType = mimeType
        }
    }

    /// Unique boundary string used to separate parts.
    public let boundary: String = UUID().uuidString
    /// Array of parts included in the multipart form.
    public var parts: [Part] = []

    /// Initializes an empty multipart form data object.
    public init() {}

    /// Adds a new part to the multipart form data.
    /// - Parameters:
    ///   - name: Form field name.
    ///   - data: Data content.
    ///   - mimeType: MIME type string.
    ///   - filename: Optional filename.
    public mutating func addPart(name: String, data: Data, mimeType: String, filename: String? = nil) {
        parts.append(Part(name: name, filename: filename, data: data, mimeType: mimeType))
    }

    /// Encodes the multipart form data into a Data object suitable for HTTP body.
    /// Uses safe UTF-8 encoding and escapes quotes in name/filename per RFC 2183.
    /// - Returns: Encoded Data representing the multipart form, or nil if any header string fails UTF-8 encoding.
    public func encodedData() -> Data? {
        guard let boundaryData = utf8Data("--\(boundary)\r\n"),
              let closingBoundaryData = utf8Data("--\(boundary)--\r\n"),
              let crlf = utf8Data("\r\n") else { return nil }
        var result = Data()
        for part in parts {
            result.append(boundaryData)
            let safeName = escapeMultipartHeaderValue(part.name)
            if let filename = part.filename {
                let safeFilename = escapeMultipartHeaderValue(filename)
                guard let line = utf8Data("Content-Disposition: form-data; name=\"\(safeName)\"; filename=\"\(safeFilename)\"\r\n"),
                      let mimeLine = utf8Data("Content-Type: \(part.mimeType)\r\n\r\n") else { return nil }
                result.append(line)
                result.append(mimeLine)
            } else {
                guard let line = utf8Data("Content-Disposition: form-data; name=\"\(safeName)\"\r\n"),
                      let mimeLine = utf8Data("Content-Type: \(part.mimeType)\r\n\r\n") else { return nil }
                result.append(line)
                result.append(mimeLine)
            }
            result.append(part.data)
            result.append(crlf)
        }
        result.append(closingBoundaryData)
        return result
    }
}

/// Errors that can occur during network operations.
public enum NetworkError: Error {
    /// URL could not be constructed.
    case invalidURL
    /// Multipart form data failed to encode (e.g. non-UTF-8 header values).
    case invalidMultipartEncoding
    /// Response data was empty.
    case emptyResponse
    /// Unauthorized access, typically HTTP 401.
    case unauthorized
    /// Response was missing or of an unexpected type.
    case invalidResponse
    /// Both body and multipartData are set, which is not allowed.
    case conflictingBodyTypes
}

/// Generic HTTP error carrying status code and payload for diagnostics.
public struct HTTPError: LocalizedError {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [AnyHashable: Any]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = normalizeHeaders(headers)
    }

    public var errorDescription: String? {
        "Request failed with status code \(statusCode)"
    }
}

/// Convenience response that only exposes the HTTP status code and headers.
/// Marked as @unchecked Sendable because Dictionary<String, String> is safe for cross-actor use in Swift 6.
public struct StatusCodeResponse: Decodable, Equatable, @unchecked Sendable {
    public let statusCode: Int
    public let headers: [String: String]

    public init(statusCode: Int, headers: [AnyHashable: Any]) {
        self.statusCode = statusCode
        self.headers = normalizeHeaders(headers)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try container.decode(Int.self, forKey: .statusCode)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case statusCode
        case headers
    }
}

/// Represents an empty payload. Useful for endpoints that only signal success via status code.
/// Marked as @unchecked Sendable for Swift 6 strict concurrency compatibility.
public struct EmptyResponse: Decodable, Equatable, @unchecked Sendable {
    public init() {}
}

/// Protocol representing a network request.
/// Conforming types define the request path, method, headers, parameters, and response type.
public protocol NetworkRequest {

    /// The expected response type, must conform to Decodable.
    associatedtype Response: Decodable

    /// The path component appended to the base URL.
    var path: String { get }
    /// HTTP method for the request.
    var method: HTTPMethod { get }
    /// Optional HTTP headers to include in the request.
    var headers: [String: String]? { get }
    /// Optional query parameters appended to the URL.
    var queryParameters: [String: String]? { get }
    /// Content-Type header for the request. Defaults to "application/json".
    var contentType: String { get }
    /// Optional body sent with the request, supporting multiple encodings.
    /// Use `RequestBody` to specify content and content type.
    var body: RequestBody? { get }
    /// Optional multipart form data for upload requests.
    var multipartData: MultipartFormData? { get }
    /// Optional progress observer for upload/download progress.
    var progress: NetworkProgress? { get }
    /// Retry policy to apply for this request.
    var retryPolicy: RetryPolicy { get }
    
    /// Optional custom error decoder to extract server-side error responses.
    var errorDecoder: ((Data) -> Error?)? { get }
    
    /// Should the request allow retries and token refresh on 401 Unauthorized?
    var allowsRetry: Bool { get }

    /// Decodes the raw response into the associated response type.
    /// Default implementation handles JSON decoding and empty-response fallbacks.
    func decodeResponse(data: Data, response: URLResponse) throws -> Response

    /// Optional handler used when the server returns an empty body.
    /// `StatusCodeResponse` and `EmptyResponse` already provide default handlers,
    /// so override this only when you need to build a custom response from the status code, headers, or other metadata.
    var emptyResponseHandler: ((HTTPURLResponse) throws -> Response)? { get }

    /// Provides a decoder instance for JSON responses.
    var jsonDecoder: JSONDecoder { get }

    /// Provides an encoder instance for JSON request bodies.
    var jsonEncoder: JSONEncoder { get }
}

/// Default implementation
public extension NetworkRequest {
    var headers: [String: String]? { nil }
    var queryParameters: [String: String]? { nil }
    var contentType: String { "application/json" }
    var body: RequestBody? { nil }
    var multipartData: MultipartFormData? { nil }
    var progress: NetworkProgress? { nil }
    var retryPolicy: RetryPolicy { RetryPolicy() }
    var errorDecoder: ((Data) -> Error?)? { nil }
    /// Default implementation for `allowsRetry` to maintain backward compatibility.
    /// Requests allow retries and token refresh on 401 by default.
    var allowsRetry: Bool { true }
    var emptyResponseHandler: ((HTTPURLResponse) throws -> Response)? { nil }
    var jsonDecoder: JSONDecoder { JSONDecoder() }
    var jsonEncoder: JSONEncoder { JSONEncoder() }

    func decodeResponse(data: Data, response: URLResponse) throws -> Response {
        if data.isEmpty {
            guard let handler = emptyResponseHandler else {
                throw NetworkError.emptyResponse
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            return try handler(httpResponse)
        }
        return try jsonDecoder.decode(Response.self, from: data)
    }

}

public extension NetworkRequest where Response == StatusCodeResponse {
    var emptyResponseHandler: ((HTTPURLResponse) throws -> StatusCodeResponse)? {
        { StatusCodeResponse(statusCode: $0.statusCode, headers: $0.allHeaderFields) }
    }
}

public extension NetworkRequest where Response == EmptyResponse {
    var emptyResponseHandler: ((HTTPURLResponse) throws -> EmptyResponse)? { { _ in EmptyResponse() } }

    func decodeResponse(data: Data, response: URLResponse) throws -> EmptyResponse {
        // Ignore server payload; success is considered sufficient.
        return EmptyResponse()
    }
}

/// Represents a request body for a network request, supporting various types including:
/// - `Encodable` for JSON payloads
/// - Raw `Data` for binary or pre-encoded content
/// - `InputStream` for large streaming uploads
/// - Form URL encoded data (`application/x-www-form-urlencoded`)
public struct RequestBody {
    /// The underlying content of the request body.
    public enum Content {
        /// JSON-encodable object
        case encodable(Encodable)
        /// Raw binary or pre-encoded data
        case raw(Data)
        /// Stream for large data uploads
        case stream(InputStream)
        /// Key-value pairs for form URL encoded data
        case formURLEncoded([String: String])
    }

    public let content: Content
    public let contentType: String

    public init(encodable: Encodable, contentType: String = "application/json") {
        self.content = .encodable(encodable)
        self.contentType = contentType
    }

    public init(data: Data, contentType: String) {
        self.content = .raw(data)
        self.contentType = contentType
    }

    public init(stream: InputStream, contentType: String) {
        self.content = .stream(stream)
        self.contentType = contentType
    }
    
    public init(formURLEncoded parameters: [String: String]) {
        self.content = .formURLEncoded(parameters)
        self.contentType = "application/x-www-form-urlencoded"
    }

}

/// Errors conforming to this protocol are not retried by the default RetryPolicy.
/// Use this for business-level or user-presentable errors instead of relying on type name checks.
public protocol NonRetriableError: Error {}

/// Defines the retry behavior for network requests, including maximum retry attempts,
/// delay between retries, and a closure to determine if a retry should occur based on the error.
public struct RetryPolicy {

    /// Maximum number of retry attempts.
    public let maxRetryCount: Int
    /// Delay in seconds before retrying a request.
    public let delay: TimeInterval
    /// Closure to determine if a request should be retried based on the encountered error.
    public let shouldRetry: (Error) -> Bool

    /// Initializes a new RetryPolicy.
    /// - Parameters:
    ///   - maxRetryCount: Maximum number of retries (default is 0).
    ///   - delay: Delay between retries in seconds (default is 1.0).
    ///   - shouldRetry: Closure to decide if retry should occur based on error.
    public init(maxRetryCount: Int = 0, delay: TimeInterval = 1.0, shouldRetry: @escaping (Error) -> Bool = {
        if case NetworkError.unauthorized = $0 { return false }
        if let urlError = $0 as? URLError {
            return urlError.code != .userAuthenticationRequired
        }
        if $0 is NonRetriableError { return false }
        return true
    }) {
        self.maxRetryCount = maxRetryCount
        self.delay = delay
        self.shouldRetry = shouldRetry
    }

}

/// Observable object to track progress of network uploads or downloads.
@MainActor
public final class NetworkProgress: ObservableObject {
    /// Fraction of task completed, ranging from 0.0 to 1.0.
    @Published public var fractionCompleted: Double = 0.0

    /// Initializes a new NetworkProgress instance.
    public init() {}
}

/// Protocol for providing token refresh functionality.
/// Implementers should handle refreshing authentication tokens as needed.
public protocol TokenRefreshProvider: AnyObject {
    /// Refreshes authentication token if needed.
    /// This method is called automatically when a 401 Unauthorized response is received.
    func refreshTokenIfNeeded() async throws
}

/// Protocol abstraction for NetworkManager to allow mocking and dependency injection.
public protocol NetworkManaging {

    var tokenRefresher: TokenRefreshProvider? { get set }

    /// Sends a network request and returns the decoded response.
    /// - Parameter request: The network request to send.
    /// - Returns: A decoded response of type `T.Response`.
    func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response
}

/// Protocol abstraction for URLSession to allow mocking and dependency injection.
public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// Manages network requests, including retries, token refresh, and progress reporting.
/// Marked as @unchecked Sendable so it can be used from async contexts (e.g. tests) without isolation errors; callers must not mutate shared state concurrently.
open class NetworkManager: NetworkManaging, @unchecked Sendable {

    /// The base URL provider; each request calls this closure to get the current base URL.
    /// Pass a closure (e.g. `{ myURL }` or `{ URL(string: "https://api.example.com")! }`) for dynamic or fixed base URL.
    private(set) public var baseURL: () -> URL
    private let session: URLSessionProtocol
    /// Optional token refresher to handle authentication token renewal.
    public var tokenRefresher: TokenRefreshProvider?
    /// User-Agent configuration. If set, automatically adds User-Agent header to all requests.
    public var userAgentConfiguration: UserAgentConfiguration?
    private let logger: Logger

    /// Initializes a `NetworkManager` with the given configuration.
    /// - Parameters:
    ///   - baseURL: The base URL that all request paths will be appended to.
    ///   - tokenRefresher: Optional token refresher for handling automatic re-authentication (e.g. refresh token logic).
    ///   - session: The `URLSessionProtocol` to use for making requests. Defaults to `URLSession.shared`.
    ///   - loggerSubsystem: The subsystem identifier used for the `Logger` instance. Defaults to "com.yourapp.networking".
    ///   - userAgentConfiguration: Optional User-Agent configuration. If provided, User-Agent header will be automatically set for all requests. If nil, User-Agent is not set.
    public init(
        baseURL: @escaping (() -> URL),
        session: URLSessionProtocol = URLSession.shared,
        loggerSubsystem: String = "com.yourapp.networking",
        userAgentConfiguration: UserAgentConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.userAgentConfiguration = userAgentConfiguration
        self.logger = Logger(subsystem: loggerSubsystem, category: "network")
    }

    /// Convenience initializer for a fixed base URL (wraps URL in a closure).
    public convenience init(
        baseURL: URL,
        session: URLSessionProtocol = URLSession.shared,
        loggerSubsystem: String = "com.yourapp.networking",
        userAgentConfiguration: UserAgentConfiguration? = nil
    ) {
        self.init(baseURL: { baseURL }, session: session, loggerSubsystem: loggerSubsystem, userAgentConfiguration: userAgentConfiguration)
    }

    /// Sends a network request and decodes the response.
    /// - Parameter request: The network request to send.
    /// - Returns: Decoded response of type `T.Response`.
    /// - Throws: Errors encountered during the request or decoding.
    public func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response {
        return try await performRequest(request, accessToken: accessToken, shouldRetry: true, attempt: 0)
    }

    /// Builds the request URL by normalizing the path, appending it to the base URL, and adding query parameters.
    private func buildRequestURL<T: NetworkRequest>(_ request: T) throws -> URL {
        guard let normalizedPath = normalizePath(request.path) else {
            throw NetworkError.invalidURL
        }
        guard var urlComponents = URLComponents(url: baseURL().appendingPathComponent(normalizedPath), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        if let query = request.queryParameters {
            urlComponents.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        return url
    }

    /// Applies default headers, authentication, Accept, and User-Agent to the request.
    private func applyCommonHeaders<T: NetworkRequest>(to urlRequest: inout URLRequest, request: T, accessToken: (() -> String?)?) {
        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let accessToken = accessToken?(),
           urlRequest.value(forHTTPHeaderField: "Authorization") == nil {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if request.contentType.contains("application/json"),
           urlRequest.value(forHTTPHeaderField: "Accept") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        if let userAgentConfig = userAgentConfiguration,
           urlRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            urlRequest.setValue(userAgentConfig.generateUserAgentString(), forHTTPHeaderField: "User-Agent")
        }
    }

    fileprivate func parseError(_ response: URLResponse, _ request: any NetworkRequest, _ data: Data) throws {
        // Decode the response data into the expected Response type.
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            if let customError = request.errorDecoder?(data) {
                throw customError
            }
            throw HTTPError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)
        }
    }

    /// Internal method to perform the network request with retry logic.
    /// - Parameters:
    ///   - request: The network request.
    ///   - shouldRetry: Flag indicating if retry is allowed (used to prevent infinite retries on 401).
    ///   - attempt: Current retry attempt count.
    /// - Returns: Decoded response.
    /// - Throws: Errors if request fails or decoding fails.
    private func performRequest<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?, shouldRetry: Bool, attempt: Int) async throws -> T.Response {
        try Task.checkCancellation()
        let url = try buildRequestURL(request)
        
        logger.info("➡️ [NETWORK] [\(request.method.rawValue)] \(request.path, privacy: .private)")
        
        var urlRequest = URLRequest(url: url)
        
        urlRequest.httpMethod = request.method.rawValue.uppercased()
        applyCommonHeaders(to: &urlRequest, request: request, accessToken: accessToken)

        // Validate that body and multipartData are not both set
        if request.body != nil && request.multipartData != nil {
            throw NetworkError.conflictingBodyTypes
        }
        
        // Set body if provided.
        if let requestBody = request.body {
            var bodyLength: Int?
            switch requestBody.content {
            case .encodable(let encodable):
                let encoder = request.jsonEncoder
                let encodedData = try encoder.encode(AnyEncodable(encodable))
                urlRequest.httpBody = encodedData
                bodyLength = encodedData.count
                // Use request.contentType instead of requestBody.contentType for better control
                urlRequest.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
            case .raw(let data):
                urlRequest.httpBody = data
                bodyLength = data.count
                // For raw data, prefer requestBody.contentType if set, otherwise use request.contentType
                urlRequest.setValue(requestBody.contentType, forHTTPHeaderField: "Content-Type")
            case .stream(let stream):
                urlRequest.httpBodyStream = stream
                // For stream, prefer requestBody.contentType if set, otherwise use request.contentType
                urlRequest.setValue(requestBody.contentType, forHTTPHeaderField: "Content-Type")
                // do not set bodyLength, as it's unknown for streams
            case .formURLEncoded(let parameters):
                var components = URLComponents()
                components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
                guard let query = components.percentEncodedQuery,
                      let data = query.data(using: .utf8) else { throw NetworkError.invalidURL }
                urlRequest.httpBody = data
                bodyLength = data.count
                // Form URL encoded always uses application/x-www-form-urlencoded
                urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
            // Set Content-Length header when known (except for streams)
            if let length = bodyLength {
                urlRequest.setValue("\(length)", forHTTPHeaderField: "Content-Length")
            }
        }

        // Set multipart form data if provided.
        if let multipart = request.multipartData {
            guard let multipartData = multipart.encodedData() else {
                throw NetworkError.invalidMultipartEncoding
            }
            urlRequest.httpBody = multipartData
            urlRequest.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("\(multipartData.count)", forHTTPHeaderField: "Content-Length")
        }

        do {
            let (data, response): (Data, URLResponse)
            if let progress = request.progress {
                (data, response) = try await ProgressSessionManager.execute(request: urlRequest, progress: progress)
            } else {
                (data, response) = try await session.data(for: urlRequest)
            }

            // Handle HTTP 401 Unauthorized response.
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Check if the request allows retry and if retries are allowed for this attempt.
                if request.allowsRetry, shouldRetry {
                    // Attempt to refresh the token. If successful, retry the request once.
                    // Note: shouldRetry is set to false to prevent infinite retry loops.
                    // The attempt count is not incremented here as this is a token refresh retry,
                    // not a regular retry policy retry. If the token refresh fails or the request
                    // still returns 401, we will throw NetworkError.unauthorized.
                    try await refreshTokenIfNeeded()
                    return try await performRequest(request, accessToken: accessToken, shouldRetry: false, attempt: attempt)
                }
                
                // Try to decode custom error after token refresh fails or is disabled
                if let customError = request.errorDecoder?(data) {
                    throw customError
                }
                // If retries are disallowed, throw unauthorized error immediately without retry or token refresh.
                throw NetworkError.unauthorized
            }
            try parseError(response, request, data)
            let decoded = try request.decodeResponse(data: data, response: response)
            logger.info("✅ [NETWORK] [\(request.method.rawValue)] \(request.path, privacy: .private) SUCCESS")
            return decoded

        } catch {
            if Task.isCancelled { throw CancellationError() }
            logger.debug("Evaluating retry policy: attempt \(attempt), max \(request.retryPolicy.maxRetryCount)")
            if attempt < request.retryPolicy.maxRetryCount, request.retryPolicy.shouldRetry(error) {
                logger.debug("Retry policy decided to retry for error: \(String(describing: error), privacy: .private)")
                logger.warning("Request failed: \(request.path, privacy: .private), attempt: \(attempt), error: \(String(describing: error), privacy: .private)")
                logger.debug("Retrying request: \(request.path, privacy: .private), next attempt: \(attempt + 1)")
                try await Task.sleep(nanoseconds: UInt64(request.retryPolicy.delay * 1_000_000_000))
                if Task.isCancelled { throw CancellationError() }
                return try await performRequest(request, accessToken: accessToken, shouldRetry: shouldRetry, attempt: attempt + 1)
            }
            logger.error("Request failed permanently: \(request.path, privacy: .private), error: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    /// Calls the token refresher to refresh authentication tokens if needed.
    /// This is triggered when a 401 Unauthorized response is received.
    private func refreshTokenIfNeeded() async throws {
        try await tokenRefresher?.refreshTokenIfNeeded()
    }
    

}


struct AnyEncodable: Encodable {
    
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }

}
