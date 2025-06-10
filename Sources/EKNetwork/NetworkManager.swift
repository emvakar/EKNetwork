//
//  EKNetwork.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import os
import Foundation

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

/// Manages network requests, including retries, token refresh, and progress reporting.
open class NetworkManager {

    private let baseURL: URL
    private let session: URLSession
    /// Optional token refresher to handle authentication token renewal.
    public weak var tokenRefresher: TokenRefreshProvider?
    private let logger: Logger

    /// Initializes a `NetworkManager` with the given configuration.
    /// - Parameters:
    ///   - baseURL: The base URL that all request paths will be appended to.
    ///   - tokenRefresher: Optional token refresher for handling automatic re-authentication (e.g. refresh token logic).
    ///   - session: The `URLSession` to use for making requests. Defaults to `URLSession.shared`.
    ///   - loggerSubsystem: The subsystem identifier used for the `Logger` instance. Defaults to "com.yourapp.networking".
    public init(baseURL: URL, tokenRefresher: TokenRefreshProvider? = nil, session: URLSession = .shared, loggerSubsystem: String = "com.yourapp.networking") {
        self.baseURL = baseURL
        self.tokenRefresher = tokenRefresher
        self.session = session
        self.logger = Logger(subsystem: loggerSubsystem, category: "network")
    }

    /// Sends a network request and decodes the response.
    /// - Parameter request: The network request to send.
    /// - Returns: Decoded response of type `T.Response`.
    /// - Throws: Errors encountered during the request or decoding.
    public func send<T: NetworkRequest>(_ request: T) async throws -> T.Response {
        return try await performRequest(request, shouldRetry: true, attempt: 0)
    }

    /// Internal method to perform the network request with retry logic.
    /// - Parameters:
    ///   - request: The network request.
    ///   - shouldRetry: Flag indicating if retry is allowed (used to prevent infinite retries on 401).
    ///   - attempt: Current retry attempt count.
    /// - Returns: Decoded response.
    /// - Throws: Errors if request fails or decoding fails.
    private func performRequest<T: NetworkRequest>(_ request: T, shouldRetry: Bool, attempt: Int) async throws -> T.Response {
    
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
        let sessionToUse: URLSession
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
                // If retry is allowed, attempt token refresh and retry once.
                guard shouldRetry else { throw NetworkError.unauthorized }
                try await refreshTokenIfNeeded()
                // Retry the request once more after refreshing token.
                return try await performRequest(request, shouldRetry: false, attempt: attempt)
            }

            logger.info("Request succeeded: \(request.path, privacy: .public)")
            // Decode the response data into the expected Response type.
            return try JSONDecoder().decode(T.Response.self, from: data)

        } catch {
            // Check if retry is allowed and retry policy permits retrying on this error.
            if attempt < request.retryPolicy.maxRetryCount, request.retryPolicy.shouldRetry(error) {
                logger.warning("Request failed: \(request.path, privacy: .public), attempt: \(attempt), error: \(String(describing: error), privacy: .public)")
                // Wait for the specified delay before retrying.
                try await Task.sleep(nanoseconds: UInt64(request.retryPolicy.delay * 1_000_000_000))
                // Retry the request with incremented attempt count.
                return try await performRequest(request, shouldRetry: shouldRetry, attempt: attempt + 1)
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
        DispatchQueue.main.async {
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
