import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct PVCListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 130, sortField: .namespace),
        ResourceTableColumn(title: "Status", key: "status", width: 100, sortField: .status),
        ResourceTableColumn(title: "Volume", key: "volume", width: 180),
        ResourceTableColumn(title: "Capacity", key: "capacity", width: 100),
        ResourceTableColumn(title: "Storage Class", key: "storageClass", width: 160),
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
                            kind: .persistentVolumeClaim,
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
                    await viewModel.deleteResource(kind: .persistentVolumeClaim, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .persistentVolumeClaim, name: resource.name, namespace: resource.namespace, client: client)
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
            core.v1.PersistentVolumeClaim.self,
            kind: .persistentVolumeClaim,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: pvcToResourceItem
        )
    }

    private nonisolated func pvcToResourceItem(_ resource: core.v1.PersistentVolumeClaim) -> ResourceItem {
        let phase = resource.status?.phase ?? "Unknown"
        let volume = resource.spec?.volumeName ?? ""
        let capacity: String
        if let qty = resource.status?.capacity?["storage"] {
            capacity = qty.description
        } else {
            capacity = ""
        }
        let storageClass = resource.spec?.storageClassName ?? ""

        return ResourceItem(
            id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
            name: resource.name ?? "",
            namespace: resource.metadata?.namespace,
            status: phase,
            age: resource.metadata?.creationTimestamp,
            labels: resource.metadata?.labels ?? [:],
            annotations: resource.metadata?.annotations ?? [:],
            kind: .persistentVolumeClaim,
            extraColumns: [
                "volume": volume,
                "capacity": capacity,
                "storageClass": storageClass,
            ]
        )
    }
}
