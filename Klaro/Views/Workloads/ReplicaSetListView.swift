import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ReplicaSetListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

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
                            kind: .replicaSet,
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
                    await viewModel.deleteResource(kind: .replicaSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onScale: { resource, replicas in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.scaleResource(kind: .replicaSet, name: resource.name, namespace: resource.namespace, replicas: replicas, client: client)
                    await loadData()
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .replicaSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
        .alert("Scale Failed", isPresented: $viewModel.showScaleError) {
            Button("OK") {}
        } message: {
            Text(viewModel.scaleError ?? "Unknown error")
        }
        .task { await loadData() }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            apps.v1.ReplicaSet.self,
            kind: .replicaSet,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: replicaSetToResourceItem
        )
    }

    private nonisolated func replicaSetToResourceItem(_ rs: apps.v1.ReplicaSet) -> ResourceItem {
        let desired = rs.spec?.replicas ?? 0
        let current = rs.status?.replicas ?? 0
        let ready = rs.status?.readyReplicas ?? 0

        let status: String
        if ready == desired && desired > 0 {
            status = "Running"
        } else if desired == 0 {
            status = "Scaled Down"
        } else {
            status = "Updating"
        }

        return ResourceItem(
            id: "\(rs.metadata?.namespace ?? "")/\(rs.name ?? "")",
            name: rs.name ?? "",
            namespace: rs.metadata?.namespace,
            status: status,
            age: rs.metadata?.creationTimestamp,
            labels: rs.metadata?.labels ?? [:],
            annotations: rs.metadata?.annotations ?? [:],
            kind: .replicaSet,
            extraColumns: [
                "desired": "\(desired)",
                "current": "\(current)",
                "ready": "\(ready)",
            ]
        )
    }
}
