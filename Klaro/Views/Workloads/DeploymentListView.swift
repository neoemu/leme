import SwiftUI
import SwiftkubeClient

struct DeploymentListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Ready", key: "ready", width: 80),
        ResourceTableColumn(title: "Up-to-date", key: "upToDate", width: 90),
        ResourceTableColumn(title: "Available", key: "available", width: 80),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewYAML: { resource in
                appState.selectResource(resource.id)
                appState.openBottomPanel(mode: .yaml)
            },
            onDelete: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.deleteResource(kind: .deployment, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onScale: { resource, replicas in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.scaleResource(kind: .deployment, name: resource.name, namespace: resource.namespace, replicas: replicas, client: client)
                    await loadDeployments()
                }
            },
            onRestart: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.restartResource(kind: .deployment, name: resource.name, namespace: resource.namespace, client: client)
                    await loadDeployments()
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .deployment, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
        .alert("Scale Failed", isPresented: $viewModel.showScaleError) {
            Button("OK") {}
        } message: {
            Text(viewModel.scaleError ?? "Unknown error")
        }
        .alert("Restart Failed", isPresented: $viewModel.showRestartError) {
            Button("OK") {}
        } message: {
            Text(viewModel.restartError ?? "Unknown error")
        }
        .task {
            await loadDeployments()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadDeployments()
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
    private func loadDeployments() async {
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            await viewModel.loadDeployments(client: client, namespace: appState.selectedNamespace)
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
            await detail.loadDeploymentDetail(name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }
}
