import Foundation
import SwiftkubeClient

@Observable
@MainActor
final class PodLogsViewModel {

    // MARK: - Properties

    let id = UUID()
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
    /// When non-empty, this session aggregates the logs of several pods
    /// (workload logs); `podName` then holds the workload name.
    var aggregatePodNames: [String] = []

    private var streamingTask: Task<Void, Never>?
    private var logStreamService: LogStreamService?
    private var aggregateTasks: [Task<Void, Never>] = []
    private var aggregateServices: [LogStreamService] = []

    // MARK: - Computed

    var filteredLogLines: [String] {
        guard !searchText.isEmpty else { return logLines }
        let query = searchText.lowercased()
        return logLines.filter { $0.lowercased().contains(query) }
    }

    var tabTitle: String {
        if !aggregatePodNames.isEmpty {
            return "\(podName) (\(aggregatePodNames.count) pods)"
        }
        if let container = selectedContainer, !container.isEmpty {
            return "\(podName):\(container)"
        }
        return podName
    }

    // MARK: - Initialization

    init(podName: String, namespace: String) {
        self.podName = podName
        self.namespace = namespace
    }

    // MARK: - Streaming

    func startStreaming(client: KubernetesClient) {
        guard aggregatePodNames.isEmpty else {
            startAggregateStreaming(client: client)
            return
        }

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

        aggregateTasks.forEach { $0.cancel() }
        aggregateTasks = []
        for service in aggregateServices {
            Task {
                await service.stopStreaming()
            }
        }
        aggregateServices = []

        isStreaming = false
    }

    // MARK: - Aggregate (Workload) Streaming

    private func startAggregateStreaming(client: KubernetesClient) {
        let pods = aggregatePodNames
        stopStreaming()

        isStreaming = true
        errorMessage = nil

        let ns = namespace
        let timestamps = showTimestamps

        for pod in pods {
            let service = LogStreamService(client: client)
            aggregateServices.append(service)

            let task = Task { [weak self] in
                do {
                    let stream = try await service.streamLogs(
                        podName: pod,
                        namespace: ns,
                        container: nil,
                        timestamps: timestamps,
                        tailLines: 50
                    )

                    for try await line in stream {
                        guard !Task.isCancelled else { break }
                        self?.appendLine("[\(pod)] \(line)")
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.appendLine("[\(pod)] ⚠ stream error: \(error.localizedDescription)")
                    }
                }
            }
            aggregateTasks.append(task)
        }
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
