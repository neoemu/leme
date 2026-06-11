import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct JobListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Completions", key: "completions", width: 100),
        ResourceTableColumn(title: "Duration", key: "duration", width: 90),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewLogs: { resource in
                appState.selectResource(resource.id)
                appState.openBottomPanel(mode: .logs)
            },
            onViewYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    do {
                        let yaml = try await viewModel.fetchResourceYAML(
                            kind: .job,
                            name: resource.name,
                            namespace: resource.namespace,
                            client: client
                        )
                        appState.showYAMLEditor(resourceID: resource.id, title: "YAML - \(resource.name)", yaml: yaml)
                    } catch {
                        appState.showYAMLEditor(
                            resourceID: resource.id,
                            title: "YAML - \(resource.name)",
                            yaml: "# Error loading YAML: \(error.localizedDescription)"
                        )
                    }
                }
            },
            onDelete: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.deleteResource(kind: .job, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .job, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .task {
            await loadResources()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadResources()
            }
        }
        .onChange(of: appState.selectedResourceID) { _, newValue in
            if let resourceID = newValue {
                Task {
                    await loadDetail(resourceID: resourceID)
                }
            } else {
                detailViewModel = nil
            }
        }
    }

    @MainActor
    private func loadResources() async {
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            await viewModel.loadNamespacedResources(
                batch.v1.Job.self,
                kind: .job,
                client: client,
                namespace: appState.selectedNamespace,
                mapper: Self.mapJob
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDetail(resourceID: String) async {
        let parts = resourceID.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let namespace = String(parts[0])
        let name = String(parts[1])

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            let detail = ResourceDetailViewModel(client: client, contextName: appState.activeCluster?.contextName)
            detailViewModel = detail
            await detail.loadDetail(batch.v1.Job.self, name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }

    private nonisolated static func mapJob(_ job: batch.v1.Job) -> ResourceItem {
        let succeeded = job.status?.succeeded ?? 0
        let completions = job.spec?.completions ?? 1

        var extra: [String: String] = [:]
        extra["completions"] = "\(succeeded)/\(completions)"

        // Calculate duration
        if let start = job.status?.startTime, let end = job.status?.completionTime {
            let duration = end.timeIntervalSince(start)
            extra["duration"] = Self.formatDuration(duration)
        } else if let start = job.status?.startTime {
            let duration = Date().timeIntervalSince(start)
            extra["duration"] = Self.formatDuration(duration)
        } else {
            extra["duration"] = "-"
        }

        let status: String
        if succeeded >= completions {
            status = "Completed"
        } else if let failed = job.status?.failed, failed > 0 {
            status = "Failed"
        } else if job.status?.active ?? 0 > 0 {
            status = "Running"
        } else {
            status = "Pending"
        }

        return ResourceItem(
            id: "\(job.metadata?.namespace ?? "")/\(job.name ?? "")",
            name: job.name ?? "",
            namespace: job.metadata?.namespace,
            status: status,
            age: job.metadata?.creationTimestamp,
            labels: job.metadata?.labels ?? [:],
            annotations: job.metadata?.annotations ?? [:],
            kind: .job,
            extraColumns: extra
        )
    }

    private nonisolated static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            return "\(days)d\(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m\(seconds % 60)s"
        } else {
            return "\(seconds)s"
        }
    }
}
