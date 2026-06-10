import Foundation
import SwiftkubeClient

@Observable
@MainActor
final class ClusterViewModel {
    var isLoading = false
    var errorMessage: String?
    var serverVersion: String?

    private let clusterManager: ClusterManager
    private var kubeconfigWatcher: KubeconfigWatcher?

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

    /// Starts watching the kubeconfig file; edits trigger a context reload
    /// that preserves the runtime state of clusters that still exist.
    func startKubeconfigWatcher(appState: AppState) {
        guard kubeconfigWatcher == nil else { return }

        let watcher = KubeconfigWatcher { [weak self, weak appState] in
            Task { @MainActor in
                guard let self, let appState else { return }
                await self.reloadContexts(appState: appState)
            }
        }
        kubeconfigWatcher = watcher
        watcher.start()
    }

    func reloadContexts(appState: AppState) async {
        await clusterManager.invalidateCache()
        do {
            let fresh = try await clusterManager.loadContexts()
            let existingByID = Dictionary(uniqueKeysWithValues: appState.clusters.map { ($0.id, $0) })

            appState.clusters = fresh.map { connection in
                guard let existing = existingByID[connection.id] else { return connection }
                var merged = connection
                merged.status = existing.status
                merged.namespaces = existing.namespaces
                merged.currentNamespace = existing.currentNamespace ?? connection.currentNamespace
                merged.serverVersion = existing.serverVersion
                merged.errorMessage = existing.errorMessage
                return merged
            }

            if let activeID = appState.activeClusterID,
               !appState.clusters.contains(where: { $0.id == activeID }) {
                appState.activeClusterID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect(cluster: ClusterConnection, appState: AppState) async {
        var updating = cluster
        updating.status = .connecting
        appState.updateCluster(updating)

        do {
            let connected = try await clusterManager.connect(connection: cluster)
            appState.updateCluster(connected)
        } catch let error as ClusterManagerError {
            // Another attempt is already running; let it finish and keep its state.
            if case .connectionInProgress = error { return }
            var failed = cluster
            failed.status = .error
            failed.errorMessage = error.localizedDescription
            appState.updateCluster(failed)
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

    /// Returns the client for the active cluster, waiting for an in-flight
    /// connection to finish instead of failing fast. This lets views trigger
    /// their load immediately after a cluster is selected: the load resumes
    /// as soon as the connection completes (or surfaces the connect error).
    func clientForActiveCluster(appState: AppState) async throws -> KubernetesClient? {
        guard let id = appState.activeClusterID else { return nil }

        let start = Date()
        let deadline = start.addingTimeInterval(Constants.clusterConnectTimeout + 2)
        // Grace window absorbing the gap between selectCluster() and the
        // connect task flipping the status to .connecting.
        let selectionGrace: TimeInterval = 1.0

        while Date() < deadline {
            guard appState.activeClusterID == id,
                  let cluster = appState.clusters.first(where: { $0.id == id }) else {
                return nil
            }

            switch cluster.status {
            case .connected:
                return try await clusterManager.client(for: id)
            case .error:
                throw ClusterManagerError.notConnected(
                    cluster.errorMessage ?? cluster.contextName
                )
            case .connecting:
                break
            case .disconnected:
                if Date().timeIntervalSince(start) > selectionGrace {
                    return nil
                }
            }

            try await Task.sleep(nanoseconds: 150_000_000)
        }

        return nil
    }
}
