//
//  ProgressSessionManager.swift
//  EKNetwork
//
//  Created by Emil Karimov on 02.02.2026.
//  Copyright © 2026 Emil Karimov. All rights reserved.
//
//  Shared URLSession with delegate for progress tracking; avoids creating a new session per request.
//

import Foundation

private final class ProgressTaskContext: @unchecked Sendable {
    let progress: NetworkProgress
    let continuation: CheckedContinuation<(Data, URLResponse), Error>
    var data = Data()
    var response: URLResponse?
    init(progress: NetworkProgress, continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        self.progress = progress
        self.continuation = continuation
    }
}

private final class ProgressDelegateManager: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var contexts: [Int: ProgressTaskContext] = [:]

    func register(taskId: Int, context: ProgressTaskContext) {
        lock.lock()
        defer { lock.unlock() }
        contexts[taskId] = context
    }

    func unregister(taskId: Int) -> ProgressTaskContext? {
        lock.lock()
        defer { lock.unlock() }
        return contexts.removeValue(forKey: taskId)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        lock.lock()
        let ctx = contexts[task.taskIdentifier]
        lock.unlock()
        guard let ctx else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            ctx.progress.fractionCompleted = fraction
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        contexts[dataTask.taskIdentifier]?.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if let ctx = contexts[dataTask.taskIdentifier] {
            ctx.data.append(data)
            let expected = dataTask.countOfBytesExpectedToReceive
            if expected > 0 {
                let fraction = min(Double(dataTask.countOfBytesReceived) / Double(expected), 1.0)
                lock.unlock()
                Task { @MainActor in
                    ctx.progress.fractionCompleted = fraction
                }
            } else {
                lock.unlock()
            }
        } else {
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ctx = unregister(taskId: task.taskIdentifier) else { return }
        if let error = error {
            ctx.continuation.resume(throwing: error)
            return
        }
        let response = ctx.response ?? URLResponse(url: task.originalRequest?.url ?? URL(string: "about:blank")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        ctx.continuation.resume(returning: (ctx.data, response))
        Task { @MainActor in
            ctx.progress.fractionCompleted = 1.0
        }
    }
}

enum ProgressSessionManager {
    private static let delegateManager = ProgressDelegateManager()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: delegateManager, delegateQueue: nil)
    }()

    /// For testing only: when set, `execute` uses this session instead of the shared one (e.g. with URLProtocol).
    nonisolated(unsafe) internal static var _testSession: URLSession?

    /// For testing only: creates a URLSession with the same delegate manager; use with _testSession for mocking.
    internal static func _createSession(configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration, delegate: delegateManager, delegateQueue: nil)
    }

    static func execute(request: URLRequest, progress: NetworkProgress) async throws -> (Data, URLResponse) {
        let sessionToUse = _testSession ?? session
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = sessionToUse.dataTask(with: request)
            let ctx = ProgressTaskContext(progress: progress, continuation: continuation)
            delegateManager.register(taskId: task.taskIdentifier, context: ctx)
            task.resume()
        }
    }
}
