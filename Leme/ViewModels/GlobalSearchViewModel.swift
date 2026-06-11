import Foundation
import SwiftkubeClient
import SwiftkubeModel

struct GlobalSearchResult: Identifiable, Sendable, Hashable {
    let kind: ResourceKind
    let name: String
    let namespace: String?
    /// Helm releases aren't Kubernetes resources; they navigate to the
    /// Installed Apps view instead of a resource table.
    var isHelmRelease: Bool = false

    var id: String { "\(isHelmRelease ? "HelmRelease" : kind.rawValue)|\(resourceID)" }

    /// Matches the id convention used by the resource tables ("ns/name" or "name").
    var resourceID: String {
        namespace.map { "\($0)/\(name)" } ?? name
    }

    var iconName: String {
        isHelmRelease ? "square.stack.3d.up" : kind.icon
    }

    var kindLabel: String {
        isHelmRelease ? "Helm Release" : kind.rawValue
    }
}

@Observable
@MainActor
final class GlobalSearchViewModel {
    var searchText: String = ""
    var selectedIndex: Int = 0
    var isLoading = false

    private var allEntries: [GlobalSearchResult] = []

    private static let maxResults = 50

    var indexedCount: Int {
        allEntries.count
    }

    var filteredResults: [GlobalSearchResult] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()

        // Exact-substring matches first, then fuzzy, both capped.
        var substring: [GlobalSearchResult] = []
        var fuzzy: [GlobalSearchResult] = []
        for entry in allEntries {
            let name = entry.name.lowercased()
            if name.contains(query) {
                substring.append(entry)
            } else if Self.fuzzyMatch(query: query, target: name) {
                fuzzy.append(entry)
            }
            if substring.count >= Self.maxResults { break }
        }
        return Array((substring + fuzzy).prefix(Self.maxResults))
    }

    /// Builds the search index by listing the main resource kinds across all
    /// namespaces. Called once when the search overlay opens.
    func loadIndex(client: KubernetesClient, contextName: String?) async {
        isLoading = true
        defer { isLoading = false }

        let service = KubernetesService(client: client)

        var entries: [GlobalSearchResult] = []

        async let pods = Self.namespacedEntries(core.v1.Pod.self, kind: .pod, service: service)
        async let deployments = Self.namespacedEntries(apps.v1.Deployment.self, kind: .deployment, service: service)
        async let statefulSets = Self.namespacedEntries(apps.v1.StatefulSet.self, kind: .statefulSet, service: service)
        async let daemonSets = Self.namespacedEntries(apps.v1.DaemonSet.self, kind: .daemonSet, service: service)
        async let cronJobs = Self.namespacedEntries(batch.v1.CronJob.self, kind: .cronJob, service: service)
        async let jobs = Self.namespacedEntries(batch.v1.Job.self, kind: .job, service: service)
        async let services = Self.namespacedEntries(core.v1.Service.self, kind: .service, service: service)
        async let ingresses = Self.namespacedEntries(networking.v1.Ingress.self, kind: .ingress, service: service)
        async let configMaps = Self.namespacedEntries(core.v1.ConfigMap.self, kind: .configMap, service: service)
        async let secrets = Self.namespacedEntries(core.v1.Secret.self, kind: .secret, service: service)
        async let pvcs = Self.namespacedEntries(core.v1.PersistentVolumeClaim.self, kind: .persistentVolumeClaim, service: service)
        async let nodes = Self.clusterScopedEntries(core.v1.Node.self, kind: .node, service: service)
        async let namespaces = Self.clusterScopedEntries(core.v1.Namespace.self, kind: .namespace, service: service)
        async let helmReleases = Self.helmEntries(contextName: contextName)

        entries += await pods
        entries += await deployments
        entries += await statefulSets
        entries += await daemonSets
        entries += await cronJobs
        entries += await jobs
        entries += await services
        entries += await ingresses
        entries += await configMaps
        entries += await secrets
        entries += await pvcs
        entries += await nodes
        entries += await namespaces
        entries += await helmReleases

        allEntries = entries
    }

    func clear() {
        searchText = ""
        selectedIndex = 0
        allEntries = []
    }

    func moveUp() {
        let count = filteredResults.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    func moveDown() {
        let count = filteredResults.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    // MARK: - Private

    private nonisolated static func namespacedEntries<R: KubernetesAPIResource & NamespacedResource & ListableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        service: KubernetesService
    ) async -> [GlobalSearchResult] where R.List.Item == R {
        guard let list = try? await service.list(type, in: nil) else { return [] }
        return list.items.compactMap { item in
            guard let name = item.name else { return nil }
            return GlobalSearchResult(kind: kind, name: name, namespace: item.metadata?.namespace)
        }
    }

    private nonisolated static func clusterScopedEntries<R: KubernetesAPIResource & ClusterScopedResource & ListableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        service: KubernetesService
    ) async -> [GlobalSearchResult] where R.List.Item == R {
        guard let list = try? await service.listClusterScoped(type) else { return [] }
        return list.items.compactMap { item in
            guard let name = item.name else { return nil }
            return GlobalSearchResult(kind: kind, name: name, namespace: nil)
        }
    }

    private nonisolated static func helmEntries(contextName: String?) async -> [GlobalSearchResult] {
        let helmService = HelmService(contextName: contextName)
        guard let releases = try? await helmService.listReleases(namespace: nil) else { return [] }
        return releases.map { release in
            // `kind` is unused for helm rows; see isHelmRelease.
            GlobalSearchResult(
                kind: .endpoint,
                name: release.name,
                namespace: release.namespace,
                isHelmRelease: true
            )
        }
    }

    private nonisolated static func fuzzyMatch(query: String, target: String) -> Bool {
        var targetIndex = target.startIndex
        for char in query {
            guard let found = target[targetIndex...].firstIndex(of: char) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }
}
