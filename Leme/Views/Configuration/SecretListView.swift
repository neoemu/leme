import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct SecretListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Type", key: "type", width: 180),
        ResourceTableColumn(title: "Data Keys", key: "dataKeys", width: 100),
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
                            kind: .secret,
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
                    await viewModel.deleteResource(kind: .secret, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .secret, name: resource.name, namespace: resource.namespace, client: client)
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
            core.v1.Secret.self,
            kind: .secret,
            client: client,
            namespace: appState.selectedNamespace
        ) { secret in
            ResourceItem(
                id: "\(secret.metadata?.namespace ?? "")/\(secret.name ?? "")",
                name: secret.name ?? "",
                namespace: secret.metadata?.namespace,
                status: "Active",
                age: secret.metadata?.creationTimestamp,
                labels: secret.metadata?.labels ?? [:],
                annotations: secret.metadata?.annotations ?? [:],
                kind: .secret,
                extraColumns: [
                    "type": secret.type ?? "Opaque",
                    "dataKeys": "\(secret.data?.count ?? 0)",
                ]
            )
        }
    }
}
