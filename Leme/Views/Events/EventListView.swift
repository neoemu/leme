import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct EventListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var autoRefreshTask: Task<Void, Never>?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Type", key: "status", width: 100, sortField: .status),
        ResourceTableColumn(title: "Reason", key: "reason", width: 140),
        ResourceTableColumn(title: "Object", key: "object", width: 260),
        ResourceTableColumn(title: "Message", key: "message"),
        ResourceTableColumn(title: "Count", key: "count", width: 70),
        ResourceTableColumn(title: "Last Seen", key: "age", width: 90, sortField: .age),
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
                            kind: .event,
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
                    await viewModel.deleteResource(kind: .event, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .event, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .task {
            // Events are a time-ordered feed: newest first by default.
            viewModel.sortField = .age
            await loadData()
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
        }
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
            core.v1.Event.self,
            kind: .event,
            client: client,
            namespace: appState.selectedNamespace
        ) { event in
            // See core.v1.Event.objectMeta: `event.metadata?.x` is always nil.
            let objectMeta = event.objectMeta
            let lastSeen = event.lastTimestamp ?? objectMeta.creationTimestamp
            return ResourceItem(
                id: "\(objectMeta.namespace ?? "")/\(objectMeta.name ?? "")",
                name: objectMeta.name ?? "",
                namespace: objectMeta.namespace,
                status: event.type ?? "Normal",
                age: lastSeen,
                labels: objectMeta.labels ?? [:],
                annotations: objectMeta.annotations ?? [:],
                kind: .event,
                extraColumns: [
                    "reason": event.reason ?? "",
                    "message": event.message ?? "",
                    "count": "\(event.count ?? 0)",
                    "object": "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")",
                ]
            )
        }
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await loadData()
            }
        }
    }
}
