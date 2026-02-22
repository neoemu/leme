import SwiftUI
import SwiftkubeClient

struct PodListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Status", key: "status", width: 110, sortField: .status),
        ResourceTableColumn(title: "Ready", key: "ready", width: 70),
        ResourceTableColumn(title: "Restarts", key: "restarts", width: 80),
        ResourceTableColumn(title: "Node", key: "node", width: 140),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewLogs: { resource in
                appState.selectResource(resource.id)
                let parts = resource.id.split(separator: "/", maxSplits: 1)
                if parts.count == 2 {
                    appState.logTargetNamespace = String(parts[0])
                    appState.logTargetPodName = String(parts[1])
                    appState.logTargetContainer = nil
                }
                appState.openBottomPanel(mode: .logs)
            },
            onShell: { resource in
                appState.selectResource(resource.id)
                appState.openBottomPanel(mode: .terminal)
            },
            onViewYAML: { resource in
                appState.selectResource(resource.id)
                appState.openBottomPanel(mode: .yaml)
            },
            onDelete: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.deleteResource(kind: .pod, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .pod, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
        .task {
            await loadPods()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadPods()
            }
        }
        .onChange(of: appState.selectedResourceID) { _, newValue in
            if let resourceID = newValue {
                Task {
                    await loadDetail(resourceID: resourceID)
                }
            } else {
                detailViewModel = nil
            }
        }
    }

    @MainActor
    private func loadPods() async {
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            await viewModel.loadPods(client: client, namespace: appState.selectedNamespace)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDetail(resourceID: String) async {
        let parts = resourceID.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let namespace = String(parts[0])
        let name = String(parts[1])

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            let detail = ResourceDetailViewModel(client: client)
            detailViewModel = detail
            await detail.loadPodDetail(name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }
}
