import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct PVListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Capacity", key: "capacity", width: 110),
        ResourceTableColumn(title: "Access Modes", key: "accessModes", width: 170),
        ResourceTableColumn(title: "Reclaim Policy", key: "reclaimPolicy", width: 150),
        ResourceTableColumn(title: "Status", key: "status", width: 110, sortField: .status),
        ResourceTableColumn(title: "Claim", key: "claim", width: 220),
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
                            kind: .persistentVolume,
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
                    await viewModel.deleteResource(kind: .persistentVolume, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .persistentVolume, name: resource.name, namespace: resource.namespace, client: client)
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
            core.v1.PersistentVolume.self,
            kind: .persistentVolume,
            client: client
        ) { resource in
            let capacity = resource.spec?.capacity?["storage"]?.description ?? ""
            let accessModes = (resource.spec?.accessModes ?? []).joined(separator: ", ")
            let reclaimPolicy = resource.spec?.persistentVolumeReclaimPolicy ?? ""
            let phase = resource.status?.phase ?? "Unknown"
            let claim: String
            if let claimRef = resource.spec?.claimRef,
               let namespace = claimRef.namespace,
               let name = claimRef.name {
                claim = "\(namespace)/\(name)"
            } else {
                claim = ""
            }

            return ResourceItem(
                id: resource.name ?? "",
                name: resource.name ?? "",
                namespace: nil,
                status: phase,
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .persistentVolume,
                extraColumns: [
                    "capacity": capacity,
                    "accessModes": accessModes,
                    "reclaimPolicy": reclaimPolicy,
                    "claim": claim,
                ]
            )
        }
    }
}
