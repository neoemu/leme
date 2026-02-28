import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct EndpointListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Endpoints", key: "endpoints", width: 100),
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
                            kind: .endpoint,
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
                    await viewModel.deleteResource(kind: .endpoint, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .endpoint, name: resource.name, namespace: resource.namespace, client: client)
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
            core.v1.Endpoints.self,
            kind: .endpoint,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: endpointToResourceItem
        )
    }

    private nonisolated func endpointToResourceItem(_ resource: core.v1.Endpoints) -> ResourceItem {
        let subsets = resource.subsets ?? []
        let endpointCount = subsets.reduce(0) { $0 + ($1.addresses?.count ?? 0) }

        return ResourceItem(
            id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
            name: resource.name ?? "",
            namespace: resource.metadata?.namespace,
            status: endpointCount > 0 ? "Active" : "None",
            age: resource.metadata?.creationTimestamp,
            labels: resource.metadata?.labels ?? [:],
            annotations: resource.metadata?.annotations ?? [:],
            kind: .endpoint,
            extraColumns: [
                "endpoints": "\(endpointCount)",
            ]
        )
    }
}
