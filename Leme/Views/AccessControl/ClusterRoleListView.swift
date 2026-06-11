import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ClusterRoleListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Rules", key: "rules", width: 90),
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
                            kind: .clusterRole,
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
                    await viewModel.deleteResource(kind: .clusterRole, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .clusterRole, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .task { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadClusterScopedResources(
            rbac.v1.ClusterRole.self,
            kind: .clusterRole,
            client: client,
            mapper: clusterRoleToResourceItem
        )
    }

    private nonisolated func clusterRoleToResourceItem(_ cr: rbac.v1.ClusterRole) -> ResourceItem {
        let rulesCount = cr.rules?.count ?? 0

        return ResourceItem(
            id: cr.name ?? "",
            name: cr.name ?? "",
            namespace: nil,
            status: "Active",
            age: cr.metadata?.creationTimestamp,
            labels: cr.metadata?.labels ?? [:],
            annotations: cr.metadata?.annotations ?? [:],
            kind: .clusterRole,
            extraColumns: [
                "rules": "\(rulesCount)",
            ]
        )
    }
}
