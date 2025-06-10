//
//  RetryPolicy.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

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
        // By default, retry for all errors except unauthorized errors.
        if case let urlError as URLError = $0 {
            return urlError.code != .userAuthenticationRequired
        }
        if case NetworkError.unauthorized = $0 {
            return false
        }
        return true
    }) {
        self.maxRetryCount = maxRetryCount
        self.delay = delay
        self.shouldRetry = shouldRetry
    }

}
