import Foundation
import SwiftkubeClient
import SwiftkubeModel

struct ResourceItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let namespace: String?
    let status: String
    let age: Date?
    let labels: [String: String]
    let annotations: [String: String]
    let kind: ResourceKind
    var extraColumns: [String: String] = [:]

    static func == (lhs: ResourceItem, rhs: ResourceItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SortField: String, Sendable {
    case name
    case namespace
    case status
    case age
}

enum SortOrder: Sendable {
    case ascending
    case descending
}

@Observable
@MainActor
final class ResourceListViewModel {
    var resources: [ResourceItem] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var sortField: SortField = .name
    var sortOrder: SortOrder = .ascending
    var selectedResourceID: String?

    private var watchTask: Task<Void, Never>?

    var filteredResources: [ResourceItem] {
        var result = resources
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { item in
                item.name.lowercased().contains(query) ||
                (item.namespace?.lowercased().contains(query) ?? false) ||
                item.status.lowercased().contains(query)
            }
        }
        result.sort { a, b in
            let cmp: Bool
            switch sortField {
            case .name:
                cmp = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .namespace:
                cmp = (a.namespace ?? "").localizedCaseInsensitiveCompare(b.namespace ?? "") == .orderedAscending
            case .status:
                cmp = a.status.localizedCaseInsensitiveCompare(b.status) == .orderedAscending
            case .age:
                cmp = (a.age ?? .distantPast) > (b.age ?? .distantPast)
            }
            return sortOrder == .ascending ? cmp : !cmp
        }
        return result
    }

    func toggleSort(field: SortField) {
        if sortField == field {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortField = field
            sortOrder = .ascending
        }
    }

    // MARK: - Pod Loading

    func loadPods(client: KubernetesClient, namespace: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let podList = try await service.list(core.v1.Pod.self, in: namespace)
            resources = podList.items.map { pod in
                podToResourceItem(pod)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Deployment Loading

    func loadDeployments(client: KubernetesClient, namespace: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.list(apps.v1.Deployment.self, in: namespace)
            resources = list.items.map { deploy in
                deploymentToResourceItem(deploy)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Generic Namespaced Loading

    func loadNamespacedResources<R: KubernetesAPIResource & NamespacedResource & ListableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        namespace: String?,
        mapper: @Sendable @escaping (R) -> ResourceItem
    ) async where R.List.Item == R {
        isLoading = true
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.list(type, in: namespace)
            resources = list.items.map(mapper)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Generic Cluster-Scoped Loading

    func loadClusterScopedResources<R: KubernetesAPIResource & ClusterScopedResource & ListableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        mapper: @Sendable @escaping (R) -> ResourceItem
    ) async where R.List.Item == R {
        isLoading = true
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.listClusterScoped(type)
            resources = list.items.map(mapper)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Watch

    func startWatch(kind: ResourceKind, client: KubernetesClient, namespace: String?) {
        stopWatch()
        let watcher = ResourceWatcher(client: client)
        watchTask = Task { [weak self] in
            let stream = await watcher.watch(kind: kind, in: namespace)
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleWatchEvent(event, kind: kind, client: client, namespace: namespace)
            }
        }
    }

    func stopWatch() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func handleWatchEvent(_ event: ResourceWatchEvent, kind: ResourceKind, client: KubernetesClient, namespace: String?) async {
        // On any change, reload the resource list for simplicity
        switch kind {
        case .pod:
            await loadPods(client: client, namespace: namespace)
        case .deployment:
            await loadDeployments(client: client, namespace: namespace)
        default:
            break
        }
    }

    // MARK: - Resource Mappers

    private nonisolated func podToResourceItem(_ pod: core.v1.Pod) -> ResourceItem {
        let phase = pod.status?.phase ?? "Unknown"
        let containerStatuses = pod.status?.containerStatuses ?? []
        let restarts = containerStatuses.reduce(0) { $0 + Int($1.restartCount) }
        let readyCount = containerStatuses.filter { $0.ready }.count
        let totalCount = containerStatuses.count

        var extra: [String: String] = [:]
        extra["ready"] = "\(readyCount)/\(totalCount)"
        extra["restarts"] = "\(restarts)"
        extra["node"] = pod.spec?.nodeName ?? ""
        extra["ip"] = pod.status?.podIP ?? ""

        return ResourceItem(
            id: "\(pod.metadata?.namespace ?? "")/\(pod.name ?? "")",
            name: pod.name ?? "",
            namespace: pod.metadata?.namespace,
            status: phase,
            age: pod.metadata?.creationTimestamp,
            labels: pod.metadata?.labels ?? [:],
            annotations: pod.metadata?.annotations ?? [:],
            kind: .pod,
            extraColumns: extra
        )
    }

    private nonisolated func deploymentToResourceItem(_ deploy: apps.v1.Deployment) -> ResourceItem {
        let replicas = deploy.status?.replicas ?? 0
        let ready = deploy.status?.readyReplicas ?? 0
        let upToDate = deploy.status?.updatedReplicas ?? 0
        let available = deploy.status?.availableReplicas ?? 0

        var extra: [String: String] = [:]
        extra["ready"] = "\(ready)/\(replicas)"
        extra["upToDate"] = "\(upToDate)"
        extra["available"] = "\(available)"

        let status: String
        if ready == replicas && replicas > 0 {
            status = "Running"
        } else if replicas == 0 {
            status = "Scaled Down"
        } else {
            status = "Updating"
        }

        return ResourceItem(
            id: "\(deploy.metadata?.namespace ?? "")/\(deploy.name ?? "")",
            name: deploy.name ?? "",
            namespace: deploy.metadata?.namespace,
            status: status,
            age: deploy.metadata?.creationTimestamp,
            labels: deploy.metadata?.labels ?? [:],
            annotations: deploy.metadata?.annotations ?? [:],
            kind: .deployment,
            extraColumns: extra
        )
    }
}
