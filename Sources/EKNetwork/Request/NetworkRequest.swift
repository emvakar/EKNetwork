//
//  NetworkRequest.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

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
}
