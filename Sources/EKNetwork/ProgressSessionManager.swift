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

/// Composite key for the delegate context table. `taskIdentifier` is only unique within a single
/// `URLSession`; when several sessions share one delegate (e.g. the shared `session` plus a test
/// session) their identifiers collide. Pairing it with `ObjectIdentifier(session)` keeps contexts
/// isolated per session.
private struct ProgressContextKey: Hashable {
    let session: ObjectIdentifier
    let taskId: Int

    init(session: URLSession, task: URLSessionTask) {
        self.session = ObjectIdentifier(session)
        self.taskId = task.taskIdentifier
    }
}

private final class ProgressDelegateManager: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private static let fallbackURL: URL = {
        if let url = URL(string: "about:blank") {
            return url
        }
        return URL(fileURLWithPath: "/")
    }()
    private let lock = NSLock()
    private var contexts: [ProgressContextKey: ProgressTaskContext] = [:]

    func register(key: ProgressContextKey, context: ProgressTaskContext) {
        lock.lock()
        defer { lock.unlock() }
        contexts[key] = context
    }

    func unregister(key: ProgressContextKey) -> ProgressTaskContext? {
        lock.lock()
        defer { lock.unlock() }
        return contexts.removeValue(forKey: key)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let key = ProgressContextKey(session: session, task: task)
        lock.lock()
        let ctx = contexts[key]
        lock.unlock()
        guard let ctx else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            ctx.progress.fractionCompleted = fraction
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let key = ProgressContextKey(session: session, task: dataTask)
        lock.lock()
        contexts[key]?.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let key = ProgressContextKey(session: session, task: dataTask)
        lock.lock()
        if let ctx = contexts[key] {
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
        guard let ctx = unregister(key: ProgressContextKey(session: session, task: task)) else { return }
        if let error = error {
            ctx.continuation.resume(throwing: error)
            return
        }
        let responseURL = task.originalRequest?.url ?? Self.fallbackURL
        let response = ctx.response ?? URLResponse(url: responseURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
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

    /// Thread-safe holder for the in-flight `URLSessionTask`. Lets the task-cancellation handler
    /// cancel the task even if cancellation arrives before the task is created (we then record the
    /// cancellation and cancel as soon as the task is set).
    private final class TaskHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false

        /// Stores the task. If cancellation already arrived, cancels it immediately.
        func set(_ newTask: URLSessionTask) {
            lock.lock()
            let shouldCancel = cancelled
            task = newTask
            lock.unlock()
            if shouldCancel { newTask.cancel() }
        }

        /// Marks as cancelled and cancels the task if it already exists.
        func cancel() {
            lock.lock()
            cancelled = true
            let current = task
            lock.unlock()
            current?.cancel()
        }
    }

    static func execute(request: URLRequest, progress: NetworkProgress) async throws -> (Data, URLResponse) {
        let sessionToUse = _testSession ?? session
        let holder = TaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                // If the surrounding Task is already cancelled, bail out before touching the network.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let task = sessionToUse.dataTask(with: request)
                let ctx = ProgressTaskContext(progress: progress, continuation: continuation)
                delegateManager.register(key: ProgressContextKey(session: sessionToUse, task: task), context: ctx)
                // Publish the task before resuming so a concurrent cancellation can reach it.
                // URLSession will resolve the continuation via didCompleteWithError(cancellation).
                holder.set(task)
                task.resume()
            }
        } onCancel: {
            holder.cancel()
        }
    }
}
