import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ClusterRoleBindingListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Role Ref", key: "roleRef", width: 180),
        ResourceTableColumn(title: "Subjects", key: "subjects", width: 80),
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
                            kind: .clusterRoleBinding,
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
                    await viewModel.deleteResource(kind: .clusterRoleBinding, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .clusterRoleBinding, name: resource.name, namespace: resource.namespace, client: client)
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
            rbac.v1.ClusterRoleBinding.self,
            kind: .clusterRoleBinding,
            client: client,
            mapper: clusterRoleBindingToResourceItem
        )
    }

    private nonisolated func clusterRoleBindingToResourceItem(_ crb: rbac.v1.ClusterRoleBinding) -> ResourceItem {
        let roleRef = "\(crb.roleRef.kind)/\(crb.roleRef.name)"
        let subjectsCount = crb.subjects?.count ?? 0

        return ResourceItem(
            id: crb.name ?? "",
            name: crb.name ?? "",
            namespace: nil,
            status: "Active",
            age: crb.metadata?.creationTimestamp,
            labels: crb.metadata?.labels ?? [:],
            annotations: crb.metadata?.annotations ?? [:],
            kind: .clusterRoleBinding,
            extraColumns: [
                "roleRef": roleRef,
                "subjects": "\(subjectsCount)",
            ]
        )
    }
}
