import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct StatefulSetListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var detailViewModel: ResourceDetailViewModel?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Ready", key: "ready", width: 80),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
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
                            kind: .statefulSet,
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
                    await viewModel.deleteResource(kind: .statefulSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onScale: { resource, replicas in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.scaleResource(kind: .statefulSet, name: resource.name, namespace: resource.namespace, replicas: replicas, client: client)
                    await loadResources()
                }
            },
            onRestart: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.restartResource(kind: .statefulSet, name: resource.name, namespace: resource.namespace, client: client)
                    await loadResources()
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .statefulSet, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .task {
            await loadResources()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadResources()
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
    private func loadResources() async {
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            await viewModel.loadNamespacedResources(
                apps.v1.StatefulSet.self,
                kind: .statefulSet,
                client: client,
                namespace: appState.selectedNamespace,
                mapper: Self.mapStatefulSet
            )
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
            let detail = ResourceDetailViewModel(client: client, contextName: appState.activeCluster?.contextName)
            detailViewModel = detail
            await detail.loadDetail(apps.v1.StatefulSet.self, name: name, namespace: namespace)
        } catch {
            // Detail loading error handled by the detail view model
        }
    }

    private nonisolated static func mapStatefulSet(_ sts: apps.v1.StatefulSet) -> ResourceItem {
        let replicas = sts.status?.replicas ?? 0
        let ready = sts.status?.readyReplicas ?? 0

        var extra: [String: String] = [:]
        extra["ready"] = "\(ready)/\(replicas)"

        let status: String
        if ready == replicas && replicas > 0 {
            status = "Running"
        } else if replicas == 0 {
            status = "Scaled Down"
        } else {
            status = "Updating"
        }

        return ResourceItem(
            id: "\(sts.metadata?.namespace ?? "")/\(sts.name ?? "")",
            name: sts.name ?? "",
            namespace: sts.metadata?.namespace,
            status: status,
            age: sts.metadata?.creationTimestamp,
            labels: sts.metadata?.labels ?? [:],
            annotations: sts.metadata?.annotations ?? [:],
            kind: .statefulSet,
            extraColumns: extra
        )
    }
}
