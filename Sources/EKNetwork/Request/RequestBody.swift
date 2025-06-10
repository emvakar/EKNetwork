//
//  RequestBody.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

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
