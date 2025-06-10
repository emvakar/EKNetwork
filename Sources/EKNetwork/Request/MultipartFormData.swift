//
//  MultipartFormData.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

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
