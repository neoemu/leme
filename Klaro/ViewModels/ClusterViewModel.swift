import Foundation
import SwiftkubeClient

@Observable
@MainActor
final class ClusterViewModel {
    var isLoading = false
    var errorMessage: String?
    var serverVersion: String?

    private let clusterManager: ClusterManager

    init(clusterManager: ClusterManager) {
        self.clusterManager = clusterManager
    }

    func loadContexts(appState: AppState) async {
        isLoading = true
        errorMessage = nil
        do {
            let connections = try await clusterManager.loadContexts()
            appState.clusters = connections
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func connect(cluster: ClusterConnection, appState: AppState) async {
        var updating = cluster
        updating.status = .connecting
        appState.updateCluster(updating)

        do {
            let connected = try await clusterManager.connect(connection: cluster)
            appState.updateCluster(connected)
        } catch {
            var failed = cluster
            failed.status = .error
            failed.errorMessage = error.localizedDescription
            appState.updateCluster(failed)
        }
    }

    func disconnect(clusterID: UUID, appState: AppState) async {
        _ = await clusterManager.disconnect(connectionID: clusterID)
        if let index = appState.clusters.firstIndex(where: { $0.id == clusterID }) {
            appState.clusters[index].status = .disconnected
            appState.clusters[index].namespaces = []
            appState.clusters[index].serverVersion = nil
        }
        if appState.activeClusterID == clusterID {
            appState.activeClusterID = nil
        }
    }

    func refreshNamespaces(for clusterID: UUID, appState: AppState) async {
        do {
            let namespaces = try await clusterManager.refreshNamespaces(for: clusterID)
            if let index = appState.clusters.firstIndex(where: { $0.id == clusterID }) {
                appState.clusters[index].namespaces = namespaces
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clientForActiveCluster(appState: AppState) async throws -> KubernetesClient? {
        guard let id = appState.activeClusterID else { return nil }
        return try await clusterManager.client(for: id)
    }
}
