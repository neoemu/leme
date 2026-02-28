import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct StorageClassListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Provisioner", key: "provisioner", width: 240),
        ResourceTableColumn(title: "Reclaim Policy", key: "reclaimPolicy", width: 150),
        ResourceTableColumn(title: "Default", key: "default", width: 90),
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
                            kind: .storageClass,
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
                    await viewModel.deleteResource(kind: .storageClass, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .storageClass, name: resource.name, namespace: resource.namespace, client: client)
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
            storage.v1.StorageClass.self,
            kind: .storageClass,
            client: client
        ) { resource in
            let annotations = resource.metadata?.annotations ?? [:]
            let isDefault = annotations["storageclass.kubernetes.io/is-default-class"] == "true"

            return ResourceItem(
                id: resource.name ?? "",
                name: resource.name ?? "",
                namespace: nil,
                status: "Active",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: annotations,
                kind: .storageClass,
                extraColumns: [
                    "provisioner": resource.provisioner,
                    "reclaimPolicy": resource.reclaimPolicy ?? "",
                    "default": isDefault ? "Yes" : "No",
                ]
            )
        }
    }
}
