import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct CronJobListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Schedule", key: "schedule", width: 120),
        ResourceTableColumn(title: "Last Schedule", key: "lastSchedule", width: 110),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    do {
                        let yaml = try await viewModel.fetchResourceYAML(
                            kind: .cronJob,
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
                    await viewModel.deleteResource(kind: .cronJob, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .cronJob, name: resource.name, namespace: resource.namespace, client: client)
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
                batch.v1.CronJob.self,
                kind: .cronJob,
                client: client,
                namespace: appState.selectedNamespace,
                mapper: Self.mapCronJob
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
            let detail = ResourceDetailViewModel(client: client)
            detailViewModel = detail
            await detail.loadDetail(batch.v1.CronJob.self, name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }

    private nonisolated static func mapCronJob(_ cronJob: batch.v1.CronJob) -> ResourceItem {
        let schedule = cronJob.spec?.schedule ?? ""
        let suspended = cronJob.spec?.suspend ?? false

        var extra: [String: String] = [:]
        extra["schedule"] = schedule

        if let lastSchedule = cronJob.status?.lastScheduleTime {
            extra["lastSchedule"] = lastSchedule.relativeAge
        } else {
            extra["lastSchedule"] = "-"
        }

        let activeCount = cronJob.status?.active?.count ?? 0

        let status: String
        if suspended {
            status = "Suspended"
        } else if activeCount > 0 {
            status = "Running"
        } else {
            status = "Active"
        }

        return ResourceItem(
            id: "\(cronJob.metadata?.namespace ?? "")/\(cronJob.name ?? "")",
            name: cronJob.name ?? "",
            namespace: cronJob.metadata?.namespace,
            status: status,
            age: cronJob.metadata?.creationTimestamp,
            labels: cronJob.metadata?.labels ?? [:],
            annotations: cronJob.metadata?.annotations ?? [:],
            kind: .cronJob,
            extraColumns: extra
        )
    }
}
