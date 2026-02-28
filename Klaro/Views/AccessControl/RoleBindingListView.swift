import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct RoleBindingListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 130, sortField: .namespace),
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
                            kind: .roleBinding,
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
                    await viewModel.deleteResource(kind: .roleBinding, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .roleBinding, name: resource.name, namespace: resource.namespace, client: client)
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
            rbac.v1.RoleBinding.self,
            kind: .roleBinding,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: roleBindingToResourceItem
        )
    }

    private nonisolated func roleBindingToResourceItem(_ rb: rbac.v1.RoleBinding) -> ResourceItem {
        let roleRef = "\(rb.roleRef.kind)/\(rb.roleRef.name)"
        let subjectsCount = rb.subjects?.count ?? 0

        return ResourceItem(
            id: "\(rb.metadata?.namespace ?? "")/\(rb.name ?? "")",
            name: rb.name ?? "",
            namespace: rb.metadata?.namespace,
            status: "Active",
            age: rb.metadata?.creationTimestamp,
            labels: rb.metadata?.labels ?? [:],
            annotations: rb.metadata?.annotations ?? [:],
            kind: .roleBinding,
            extraColumns: [
                "roleRef": roleRef,
                "subjects": "\(subjectsCount)",
            ]
        )
    }
}
