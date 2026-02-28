import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ServiceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Type", key: "type", width: 110),
        ResourceTableColumn(title: "Cluster IP", key: "clusterIP", width: 140),
        ResourceTableColumn(title: "Ports", key: "ports", width: 180),
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
                            kind: .service,
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
                    await viewModel.deleteResource(kind: .service, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .service, name: resource.name, namespace: resource.namespace, client: client)
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
            core.v1.Service.self,
            kind: .service,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: serviceToResourceItem
        )
    }

    private nonisolated func serviceToResourceItem(_ resource: core.v1.Service) -> ResourceItem {
        let serviceType = resource.spec?.type ?? ""
        let clusterIP = resource.spec?.clusterIP ?? ""
        let ports = (resource.spec?.ports ?? []).map { port in
            let portNum = port.port
            let proto = port.protocol ?? "TCP"
            return "\(portNum)/\(proto)"
        }.joined(separator: ", ")

        return ResourceItem(
            id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
            name: resource.name ?? "",
            namespace: resource.metadata?.namespace,
            status: "Active",
            age: resource.metadata?.creationTimestamp,
            labels: resource.metadata?.labels ?? [:],
            annotations: resource.metadata?.annotations ?? [:],
            kind: .service,
            extraColumns: [
                "type": serviceType,
                "clusterIP": clusterIP,
                "ports": ports,
            ]
        )
    }
}
