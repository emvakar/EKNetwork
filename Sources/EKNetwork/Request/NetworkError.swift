//
//  NetworkError.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

/// Errors that can occur during network operations.
public enum NetworkError: Error {
    /// URL could not be constructed.
    case invalidURL
    /// Response data was empty.
    case emptyResponse
    /// Unauthorized access, typically HTTP 401.
    case unauthorized
}
