import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct IngressListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Hosts", key: "hosts", width: 220),
        ResourceTableColumn(title: "Paths", key: "paths", width: 220),
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
                            kind: .ingress,
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
                    await viewModel.deleteResource(kind: .ingress, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .ingress, name: resource.name, namespace: resource.namespace, client: client)
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
            networking.v1.Ingress.self,
            kind: .ingress,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: ingressToResourceItem
        )
    }

    private nonisolated func ingressToResourceItem(_ resource: networking.v1.Ingress) -> ResourceItem {
        let rules = resource.spec?.rules ?? []
        let hosts = rules.compactMap { $0.host }.joined(separator: ", ")
        let paths = rules.flatMap { rule in
            (rule.http?.paths ?? []).map { $0.path ?? "/" }
        }.joined(separator: ", ")

        return ResourceItem(
            id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
            name: resource.name ?? "",
            namespace: resource.metadata?.namespace,
            status: "Active",
            age: resource.metadata?.creationTimestamp,
            labels: resource.metadata?.labels ?? [:],
            annotations: resource.metadata?.annotations ?? [:],
            kind: .ingress,
            extraColumns: [
                "hosts": hosts,
                "paths": paths,
            ]
        )
    }
}
