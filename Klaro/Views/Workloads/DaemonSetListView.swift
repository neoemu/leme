import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct DaemonSetListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Desired", key: "desired", width: 70),
        ResourceTableColumn(title: "Current", key: "current", width: 70),
        ResourceTableColumn(title: "Ready", key: "ready", width: 70),
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
                            kind: .daemonSet,
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
                    await viewModel.deleteResource(kind: .daemonSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onRestart: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.restartResource(kind: .daemonSet, name: resource.name, namespace: resource.namespace, client: client)
                    await loadResources()
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .daemonSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
        .alert("Restart Failed", isPresented: $viewModel.showRestartError) {
            Button("OK") {}
        } message: {
            Text(viewModel.restartError ?? "Unknown error")
        }
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
                apps.v1.DaemonSet.self,
                kind: .daemonSet,
                client: client,
                namespace: appState.selectedNamespace,
                mapper: Self.mapDaemonSet
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
            await detail.loadDetail(apps.v1.DaemonSet.self, name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }

    private nonisolated static func mapDaemonSet(_ ds: apps.v1.DaemonSet) -> ResourceItem {
        let desired = ds.status?.desiredNumberScheduled ?? 0
        let current = ds.status?.currentNumberScheduled ?? 0
        let ready = ds.status?.numberReady ?? 0

        var extra: [String: String] = [:]
        extra["desired"] = "\(desired)"
        extra["current"] = "\(current)"
        extra["ready"] = "\(ready)"

        let status: String
        if ready == desired && desired > 0 {
            status = "Running"
        } else if desired == 0 {
            status = "Scaled Down"
        } else {
            status = "Updating"
        }

        return ResourceItem(
            id: "\(ds.metadata?.namespace ?? "")/\(ds.name ?? "")",
            name: ds.name ?? "",
            namespace: ds.metadata?.namespace,
            status: status,
            age: ds.metadata?.creationTimestamp,
            labels: ds.metadata?.labels ?? [:],
            annotations: ds.metadata?.annotations ?? [:],
            kind: .daemonSet,
            extraColumns: extra
        )
    }
}
