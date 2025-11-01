//
//  EKNetwork.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import os
import Foundation

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
    /// - Returns: Encoded Data representing the multipart form.
    public func encodedData() -> Data {
        var result = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        
        for part in parts {
            result.append(Data(boundaryPrefix.utf8))
            if let filename = part.filename {
                result.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            } else {
                result.append("Content-Disposition: form-data; name=\"\(part.name)\"\r\n".data(using: .utf8)!)
            }
            result.append("Content-Type: \(part.mimeType)\r\n\r\n".data(using: .utf8)!)
            result.append(part.data)
            result.append("\r\n".data(using: .utf8)!)
        }
        
        result.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return result
    }
}

/// Errors that can occur during network operations.
public enum NetworkError: Error {
    /// URL could not be constructed.
    case invalidURL
    /// Response data was empty.
    case emptyResponse
    /// Unauthorized access, typically HTTP 401.
    case unauthorized
    /// Response was missing or of an unexpected type.
    case invalidResponse
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
public struct StatusCodeResponse: Decodable, Equatable {
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
public struct EmptyResponse: Decodable, Equatable {
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

}

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
        // Do not retry on known business logic errors or unauthorized access
        if case NetworkError.unauthorized = $0 {
        return false
    }
        if let urlError = $0 as? URLError {
        return urlError.code != .userAuthenticationRequired
    }
        // Do not retry errors that are already user-presentable or business-level
        let typeName = String(describing: type(of: $0))
        if typeName.contains("APIError") || typeName.contains("ServerError") || typeName.contains("Business") {
        return false
    }
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
open class NetworkManager: NetworkManaging {

    /// The base URL that all request paths will be appended to.
    /// Can be changed dynamically using `updateBaseURL(_:)` method.
    private(set) public var baseURL: URL
    private let session: URLSessionProtocol
    /// Optional token refresher to handle authentication token renewal.
    public var tokenRefresher: TokenRefreshProvider?
    private let logger: Logger

    /// Initializes a `NetworkManager` with the given configuration.
    /// - Parameters:
    ///   - baseURL: The base URL that all request paths will be appended to.
    ///   - tokenRefresher: Optional token refresher for handling automatic re-authentication (e.g. refresh token logic).
    ///   - session: The `URLSessionProtocol` to use for making requests. Defaults to `URLSession.shared`.
    ///   - loggerSubsystem: The subsystem identifier used for the `Logger` instance. Defaults to "com.yourapp.networking".
    public init(baseURL: URL, session: URLSessionProtocol = URLSession.shared, loggerSubsystem: String = "com.yourapp.networking") {
        self.baseURL = baseURL
        self.session = session
        self.logger = Logger(subsystem: loggerSubsystem, category: "network")
    }

    /// Updates the base URL for all subsequent network requests.
    /// - Parameter newBaseURL: The new base URL to use.
    /// - Note: This change takes effect immediately for all new requests.
    ///         Requests that are currently in progress will still use the old base URL.
    public func updateBaseURL(_ newBaseURL: URL) {
        logger.info("🔄 [NETWORK] Base URL updated from \(self.baseURL.absoluteString, privacy: .public) to \(newBaseURL.absoluteString, privacy: .public)")
        self.baseURL = newBaseURL
    }

    /// Sends a network request and decodes the response.
    /// - Parameter request: The network request to send.
    /// - Returns: Decoded response of type `T.Response`.
    /// - Throws: Errors encountered during the request or decoding.
    public func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response {
        return try await performRequest(request, accessToken: accessToken, shouldRetry: true, attempt: 0)
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
        // Construct URLComponents based on baseURL and request path.
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        // Append query parameters if provided.
        if let query = request.queryParameters {
            urlComponents.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        logger.info("➡️ [NETWORK] [\(request.method.rawValue)] \(request.path, privacy: .public)")
        
        var urlRequest = URLRequest(url: url)
        
        urlRequest.httpMethod = request.method.rawValue

        // Set headers if provided.
        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let accessToken = accessToken?(),
           urlRequest.value(forHTTPHeaderField: "Authorization") == nil {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        // Set Accept header to application/json if Content-Type is application/json and Accept is not already set
        if request.contentType.contains("application/json"),
           urlRequest.value(forHTTPHeaderField: "Accept") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
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
            urlRequest.httpBody = multipart.encodedData()
            urlRequest.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        }

        // Use a URLSession with delegate for progress if needed.
        let sessionToUse: URLSessionProtocol
        if let progress = request.progress {
            let delegate = ProgressDelegate(progress: progress)
            sessionToUse = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            sessionToUse = session
        }

        do {
            // Perform network data task.
            let (data, response) = try await sessionToUse.data(for: urlRequest)

            // Handle HTTP 401 Unauthorized response.
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Check if the request allows retry and if retries are allowed for this attempt.
                if request.allowsRetry, shouldRetry {
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
            logger.info("✅ [NETWORK] [\(request.method.rawValue)] \(request.path, privacy: .public) SUCCESS")
            return decoded

        } catch {
            logger.debug("Evaluating retry policy: attempt \(attempt), max \(request.retryPolicy.maxRetryCount)")
            if attempt < request.retryPolicy.maxRetryCount, request.retryPolicy.shouldRetry(error) {
                logger.debug("Retry policy decided to retry for error: \(String(describing: error), privacy: .public)")
                logger.warning("Request failed: \(request.path, privacy: .public), attempt: \(attempt), error: \(String(describing: error), privacy: .public)")
                logger.debug("Retrying request: \(request.path, privacy: .public), next attempt: \(attempt + 1)")
                // Wait for the specified delay before retrying.
                try await Task.sleep(nanoseconds: UInt64(request.retryPolicy.delay * 1_000_000_000))
                // Retry the request with incremented attempt count.
                return try await performRequest(request, accessToken: accessToken, shouldRetry: shouldRetry, attempt: attempt + 1)
            }
            // Log permanent failure and rethrow the error.
            logger.error("Request failed permanently: \(request.path, privacy: .public), error: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Calls the token refresher to refresh authentication tokens if needed.
    /// This is triggered when a 401 Unauthorized response is received.
    private func refreshTokenIfNeeded() async throws {
        try await tokenRefresher?.refreshTokenIfNeeded()
    }

}

/// URLSession delegate implementation to report upload and download progress.
final class ProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    private let progress: NetworkProgress

    /// Initializes the delegate with a NetworkProgress instance.
    /// - Parameter progress: The progress object to update.
    init(progress: NetworkProgress) {
        self.progress = progress
    }

    /// Delegate method called periodically to report upload progress.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        // Update progress on the main thread to keep UI in sync.
        Task { @MainActor in
            self.progress.fractionCompleted = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let expected = dataTask.countOfBytesExpectedToReceive
        guard expected > 0 else { return }
        let received = dataTask.countOfBytesReceived
        let fraction = min(Double(received) / Double(expected), 1.0)
        Task { @MainActor in
            self.progress.fractionCompleted = fraction
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            self.progress.fractionCompleted = 1.0
        }
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
