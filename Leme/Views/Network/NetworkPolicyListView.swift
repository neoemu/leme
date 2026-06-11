import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct NetworkPolicyListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 130, sortField: .namespace),
        ResourceTableColumn(title: "Pod Selector", key: "podSelector", width: 180),
        ResourceTableColumn(title: "Policy Types", key: "policyTypes", width: 140),
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
                            kind: .networkPolicy,
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
                    await viewModel.deleteResource(kind: .networkPolicy, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .networkPolicy, name: resource.name, namespace: resource.namespace, client: client)
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
            networking.v1.NetworkPolicy.self,
            kind: .networkPolicy,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: networkPolicyToResourceItem
        )
    }

    private nonisolated func networkPolicyToResourceItem(_ np: networking.v1.NetworkPolicy) -> ResourceItem {
        let matchLabels = np.spec?.podSelector?.matchLabels ?? [:]
        let podSelector = matchLabels.isEmpty
            ? "<all>"
            : matchLabels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")

        let policyTypes = np.spec?.policyTypes?.joined(separator: ", ") ?? "-"

        return ResourceItem(
            id: "\(np.metadata?.namespace ?? "")/\(np.name ?? "")",
            name: np.name ?? "",
            namespace: np.metadata?.namespace,
            status: "Active",
            age: np.metadata?.creationTimestamp,
            labels: np.metadata?.labels ?? [:],
            annotations: np.metadata?.annotations ?? [:],
            kind: .networkPolicy,
            extraColumns: [
                "podSelector": podSelector,
                "policyTypes": policyTypes,
            ]
        )
    }
}
