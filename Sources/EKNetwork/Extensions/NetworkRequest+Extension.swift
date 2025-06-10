//
//  NetworkRequest+Extension.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.06.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

public extension NetworkRequest {
    var headers: [String: String]? { nil }
    var queryParameters: [String: String]? { nil }
    var body: RequestBody? { nil }
    var multipartData: MultipartFormData? { nil }
    var progress: NetworkProgress? { nil }
    var retryPolicy: RetryPolicy { RetryPolicy() }
}
