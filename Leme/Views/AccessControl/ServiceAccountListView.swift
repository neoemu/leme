import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ServiceAccountListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Secrets", key: "secrets", width: 90),
        ResourceTableColumn(title: "Age", key: "age", width: 70, sortField: .age),
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
                            kind: .serviceAccount,
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
                    await viewModel.deleteResource(kind: .serviceAccount, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .serviceAccount, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .task { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            core.v1.ServiceAccount.self,
            kind: .serviceAccount,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: serviceAccountToResourceItem
        )
    }

    private nonisolated func serviceAccountToResourceItem(_ resource: core.v1.ServiceAccount) -> ResourceItem {
        let secretsCount = resource.secrets?.count ?? 0

        return ResourceItem(
            id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
            name: resource.name ?? "",
            namespace: resource.metadata?.namespace,
            status: "Active",
            age: resource.metadata?.creationTimestamp,
            labels: resource.metadata?.labels ?? [:],
            annotations: resource.metadata?.annotations ?? [:],
            kind: .serviceAccount,
            extraColumns: [
                "secrets": "\(secretsCount)",
            ]
        )
    }
}
