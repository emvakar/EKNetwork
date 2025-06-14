//
//  EKNetwork.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import os
import Foundation

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
}

/// Default implementation
public extension NetworkRequest {
    var headers: [String: String]? { nil }
    var queryParameters: [String: String]? { nil }
    var body: RequestBody? { nil }
    var multipartData: MultipartFormData? { nil }
    var progress: NetworkProgress? { nil }
    var retryPolicy: RetryPolicy { RetryPolicy() }
    var errorDecoder: ((Data) -> Error?)? { nil }
    /// Default implementation for `allowsRetry` to maintain backward compatibility.
    /// Requests allow retries and token refresh on 401 by default.
    var allowsRetry: Bool { true }

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
    ///   - maxRetryCount: Maximum number of retries (default is 1).
    ///   - delay: Delay between retries in seconds (default is 1.0).
    ///   - shouldRetry: Closure to decide if retry should occur based on error.
    public init(maxRetryCount: Int = 1, delay: TimeInterval = 1.0, shouldRetry: @escaping (Error) -> Bool = {
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

    private let baseURL: URL
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

    /// Sends a network request and decodes the response.
    /// - Parameter request: The network request to send.
    /// - Returns: Decoded response of type `T.Response`.
    /// - Throws: Errors encountered during the request or decoding.
    public func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response {
        return try await performRequest(request, accessToken: accessToken, shouldRetry: true, attempt: 0)
    }

    fileprivate func parseError(_ response: URLResponse, _ request: NetworkRequest, _ data: Data) throws {
        // Decode the response data into the expected Response type.
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            if let customError = request.errorDecoder?(data) {
                throw customError
            }
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

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // Set headers if provided.
        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        if let accessToken = accessToken?() {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        // Set body if provided.
        if let requestBody = request.body {
            var bodyLength: Int?
            switch requestBody.content {
            case .encodable(let encodable):
                let encoder = JSONEncoder()
                let encodedData = try encoder.encode(AnyEncodable(encodable))
                urlRequest.httpBody = encodedData
                bodyLength = encodedData.count
                urlRequest.setValue(requestBody.contentType, forHTTPHeaderField: "Content-Type")
            case .raw(let data):
                urlRequest.httpBody = data
                bodyLength = data.count
                urlRequest.setValue(requestBody.contentType, forHTTPHeaderField: "Content-Type")
            case .stream(let stream):
                urlRequest.httpBodyStream = stream
                urlRequest.setValue(requestBody.contentType, forHTTPHeaderField: "Content-Type")
                // do not set bodyLength, as it's unknown for streams
            case .formURLEncoded(let parameters):
                let query = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
                guard let data = query.data(using: .utf8) else { throw NetworkError.invalidURL }
                urlRequest.httpBody = data
                bodyLength = data.count
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
            logger.info("Request succeeded: \(request.path, privacy: .public)")
            return try JSONDecoder().decode(T.Response.self, from: data)

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

/// URLSessionTaskDelegate implementation to report upload progress.
final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    
    private let progress: NetworkProgress

    /// Initializes the delegate with a NetworkProgress instance.
    /// - Parameter progress: The progress object to update.
    init(progress: NetworkProgress) {
        self.progress = progress
    }

    /// Delegate method called periodically to report upload progress.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        // Update progress on the main thread to keep UI in sync.
        Task { @MainActor in
            self.progress.fractionCompleted = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
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
