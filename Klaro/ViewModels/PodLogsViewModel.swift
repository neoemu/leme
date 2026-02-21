import Foundation
import SwiftkubeClient

@Observable
@MainActor
final class PodLogsViewModel {

    // MARK: - Properties

    var logLines: [String] = []
    var isFollowing: Bool = true
    var isStreaming: Bool = false
    var searchText: String = ""
    var selectedContainer: String?
    var availableContainers: [String] = []
    var showTimestamps: Bool = false
    var podName: String
    var namespace: String
    var errorMessage: String?

    private var streamingTask: Task<Void, Never>?
    private var logStreamService: LogStreamService?

    // MARK: - Computed

    var filteredLogLines: [String] {
        guard !searchText.isEmpty else { return logLines }
        let query = searchText.lowercased()
        return logLines.filter { $0.lowercased().contains(query) }
    }

    // MARK: - Initialization

    init(podName: String, namespace: String) {
        self.podName = podName
        self.namespace = namespace
    }

    // MARK: - Streaming

    func startStreaming(client: KubernetesClient) {
        stopStreaming()

        isStreaming = true
        errorMessage = nil

        let service = LogStreamService(client: client)
        logStreamService = service

        let pod = podName
        let ns = namespace
        let container = selectedContainer
        let timestamps = showTimestamps

        streamingTask = Task { [weak self] in
            do {
                let stream = try await service.streamLogs(
                    podName: pod,
                    namespace: ns,
                    container: container,
                    timestamps: timestamps,
                    tailLines: 100
                )

                for try await line in stream {
                    guard !Task.isCancelled else { break }
                    self?.appendLine(line)
                }

                await MainActor.run {
                    self?.isStreaming = false
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self?.errorMessage = error.localizedDescription
                        self?.isStreaming = false
                    }
                }
            }
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        if let service = logStreamService {
            Task {
                await service.stopStreaming()
            }
            logStreamService = nil
        }

        isStreaming = false
    }

    func clearLogs() {
        logLines = []
    }

    // MARK: - Non-Streaming Fetch

    func fetchLogs(client: KubernetesClient, tailLines: Int = 500) {
        stopStreaming()
        errorMessage = nil

        let service = LogStreamService(client: client)
        let pod = podName
        let ns = namespace
        let container = selectedContainer
        let timestamps = showTimestamps

        Task { [weak self] in
            do {
                let logs = try await service.fetchLogs(
                    podName: pod,
                    namespace: ns,
                    container: container,
                    timestamps: timestamps,
                    tailLines: tailLines
                )

                await MainActor.run {
                    let lines = logs.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    self?.logLines = lines
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Private

    private func appendLine(_ line: String) {
        logLines.append(line)
        if logLines.count > Constants.logBufferMaxLines {
            logLines.removeFirst(logLines.count - Constants.logBufferMaxLines)
        }
    }
}
