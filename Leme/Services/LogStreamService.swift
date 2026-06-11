import Foundation
import SwiftkubeClient
import SwiftkubeModel

// MARK: - LogStreamError

enum LogStreamError: LocalizedError, Sendable {
    case podNotFound(String)
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .podNotFound(let name):
            return "Pod '\(name)' not found"
        case .streamFailed(let detail):
            return "Log stream failed: \(detail)"
        }
    }
}

// MARK: - LogStreamService

/// Actor that wraps SwiftkubeClient's pod log streaming capabilities.
/// Provides AsyncThrowingStream<String, Error> for consuming log lines
/// with support for follow mode, container selection, tail lines, and timestamps.
actor LogStreamService {

    // MARK: - Properties

    private let client: KubernetesClient
    private var activeTask: SwiftkubeClientTask<String>?
    private var followTask: Task<Void, Never>?

    // MARK: - Initialization

    init(client: KubernetesClient) {
        self.client = client
    }

    // MARK: - Log Operations

    /// Fetches logs for a pod as a single string (non-streaming).
    ///
    /// - Parameters:
    ///   - podName: The name of the pod.
    ///   - namespace: The namespace of the pod.
    ///   - container: Optional container name. Required if the pod has multiple containers.
    ///   - previous: Whether to fetch logs from the previous instance of the container.
    ///   - timestamps: Whether to include timestamps on each log line.
    ///   - tailLines: Number of lines from the end to return. nil returns all.
    /// - Returns: The log output as a single string.
    func fetchLogs(
        podName: String,
        namespace: String,
        container: String? = nil,
        previous: Bool = false,
        timestamps: Bool = false,
        tailLines: Int? = nil
    ) async throws -> String {
        try await client.pods.logs(
            in: .namespace(namespace),
            name: podName,
            container: container,
            previous: previous,
            timestamps: timestamps,
            tailLines: tailLines
        )
    }

    /// Streams (follows) logs for a pod, returning an AsyncThrowingStream of individual log lines.
    ///
    /// - Parameters:
    ///   - podName: The name of the pod.
    ///   - namespace: The namespace of the pod.
    ///   - container: Optional container name. Required if the pod has multiple containers.
    ///   - timestamps: Whether to include timestamps on each log line.
    ///   - tailLines: Number of initial lines from the end to return. nil returns all.
    /// - Returns: An AsyncThrowingStream that yields log lines as they arrive.
    func streamLogs(
        podName: String,
        namespace: String,
        container: String? = nil,
        timestamps: Bool = false,
        tailLines: Int? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Cancel any existing follow task
        await stopStreaming()

        let task = try await client.pods.follow(
            in: .namespace(namespace),
            name: podName,
            container: container,
            timestamps: timestamps,
            tailLines: tailLines,
            retryStrategy: RetryStrategy(
                policy: .maxAttempts(5),
                backoff: .exponential(maximumDelay: 30.0, multiplier: 2.0),
                initialDelay: 1.0,
                jitter: 0.2
            )
        )

        activeTask = task
        let rawStream = await task.start()

        // Transform the raw stream into individual lines
        return AsyncThrowingStream<String, Error> { continuation in
            let lineTask = Task {
                do {
                    for try await chunk in rawStream {
                        guard !Task.isCancelled else { break }
                        // Each chunk might contain multiple lines
                        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                        for line in lines {
                            let lineStr = String(line)
                            if !lineStr.isEmpty {
                                continuation.yield(lineStr)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                lineTask.cancel()
            }

            self.followTask = lineTask
        }
    }

    /// Stops the current log streaming session.
    func stopStreaming() async {
        followTask?.cancel()
        followTask = nil
        if let task = activeTask {
            await task.cancel()
            activeTask = nil
        }
    }

    /// Returns whether a log stream is currently active.
    var isStreaming: Bool {
        activeTask != nil
    }
}
