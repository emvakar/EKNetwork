//
//  ProgressDelegate.swift
//  EKNetwork
//
//  Created by Emil Karimov on 10.12.2025.
//  Copyright © 2025 Emil Karimov. All rights reserved.
//

import Foundation

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
        // NetworkProgress is @MainActor, so we need to update on the main actor
        // Note: delegateQueue is set to nil (main queue), but we use Task for safety
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
        // NetworkProgress is @MainActor, so we need to update on the main actor
        Task { @MainActor in
            self.progress.fractionCompleted = fraction
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else { return }
        // NetworkProgress is @MainActor, so we need to update on the main actor
        Task { @MainActor in
            self.progress.fractionCompleted = 1.0
        }
    }

}

