import AppKit
import Foundation
import SwiftkubeClient
import SwiftkubeModel
import UniformTypeIdentifiers

enum PodStatusFormatter {
    static func readySummary(for pod: core.v1.Pod) -> (ready: Int, total: Int) {
        let containerStatuses = pod.status?.containerStatuses ?? []
        let ready = containerStatuses.filter(\.ready).count
        let declaredTotal = pod.spec?.containers.count ?? 0
        let observedTotal = containerStatuses.count
        let total = max(declaredTotal, observedTotal)
        return (ready, total)
    }

    static func restartCount(for pod: core.v1.Pod) -> Int {
        let containerStatuses = pod.status?.containerStatuses ?? []
        return containerStatuses.reduce(0) { $0 + Int($1.restartCount) }
    }

    static func displayStatus(for pod: core.v1.Pod) -> String {
        if pod.metadata?.deletionTimestamp != nil {
            return "Terminating"
        }

        let phase = pod.status?.phase ?? "Unknown"
        let initStatuses = pod.status?.initContainerStatuses ?? []
        let containerStatuses = pod.status?.containerStatuses ?? []
        let readiness = readySummary(for: pod)

        for status in initStatuses {
            if let waiting = status.state?.waiting?.reason, !waiting.isEmpty {
                return "Init:\(waiting)"
            }
            if let terminated = status.state?.terminated, terminated.exitCode != 0 {
                let reason = terminated.reason ?? "Error"
                return "Init:\(reason)"
            }
        }

        if let waitingReason = containerStatuses
            .compactMap({ $0.state?.waiting?.reason })
            .first(where: { !$0.isEmpty }) {
            return waitingReason
        }

        if phase == "Running", readiness.total > 0, readiness.ready < readiness.total {
            return "NotReady"
        }

        if let terminatedReason = containerStatuses
            .compactMap({ $0.state?.terminated?.reason })
            .first(where: { !$0.isEmpty }),
           phase != "Succeeded" {
            return terminatedReason
        }

        return phase
    }
}

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
    // Numeric usage values backing the CPU/Memory sortable columns
    var cpuCores: Double?
    var memoryBytes: Double?
}

enum SortField: String, Sendable {
    case name
    case namespace
    case status
    case age
    case cpu
    case memory
}

enum SortOrder: Sendable {
    case ascending
    case descending
}

enum ResourceOperationState: Sendable, Equatable {
    case idle
    case running(String)
    case success(String)
    case error(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .running(let message), .success(let message), .error(let message):
            return message
        }
    }
}

enum LiveWatchStatus: Sendable, Equatable {
    case off
    case syncing
    case live(lastEventAt: Date?)
    case recovering(lastEventAt: Date?, reason: String?)
}

@Observable
@MainActor
final class ResourceListViewModel {
    private struct LiveWatchContext: Equatable {
        let kind: ResourceKind
        let namespace: String?
        let clientIdentity: ObjectIdentifier
    }

    var resources: [ResourceItem] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var sortField: SortField = .name
    var sortOrder: SortOrder = .ascending
    var selectedResourceID: String?
    var deleteError: String?
    var showDeleteError = false
    var restartError: String?
    var showRestartError = false
    var scaleError: String?
    var showScaleError = false
    var operationState: ResourceOperationState = .idle
    var liveWatchStatus: LiveWatchStatus = .off

    private static let watchHealthPollIntervalNanoseconds: UInt64 = 1_000_000_000
    private static let podMetricsRefreshIntervalNanoseconds: UInt64 = 10_000_000_000

    private var watcher: ResourceWatcher?
    private var watchTask: Task<Void, Never>?
    private var fallbackResyncTask: Task<Void, Never>?
    private var watchHealthTask: Task<Void, Never>?
    private var podMetricsTask: Task<Void, Never>?
    private var operationResetTask: Task<Void, Never>?
    private var liveWatchContext: LiveWatchContext?
    private var resyncAction: (@MainActor () async -> Void)?
    private var isPerformingResync = false
    private var podUsageMetricsCache: [String: PodUsageMetricsSample] = [:]
    private var podUsageMetricsFetchedAt: Date?
    private var podUsageMetricsNamespaceKey: String?

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
            case .cpu:
                // First click surfaces the biggest consumers (like age: newest first)
                cmp = (a.cpuCores ?? -1) > (b.cpuCores ?? -1)
            case .memory:
                cmp = (a.memoryBytes ?? -1) > (b.memoryBytes ?? -1)
            }
            return sortOrder == .ascending ? cmp : !cmp
        }
        return result
    }

    var hasLiveWatch: Bool {
        if case .off = liveWatchStatus { return false }
        return true
    }

    var liveWatchStatusText: String {
        switch liveWatchStatus {
        case .off:
            return "Live sync off"
        case .syncing:
            return "Syncing"
        case .live(let lastEventAt):
            if let lastEventAt {
                let age = Int(max(0, Date().timeIntervalSince(lastEventAt)))
                return "Live (\(age)s)"
            }
            return "Live"
        case .recovering(_, _):
            return "Recovering"
        }
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

    func loadPods(client: KubernetesClient, namespace: String?, contextName: String? = nil) async {
        await loadPodsSnapshot(client: client, namespace: namespace, contextName: contextName, showLoading: true)
        configureLiveWatch(
            core.v1.Pod.self,
            kind: .pod,
            client: client,
            namespace: namespace,
            mapper: { Self.basePodItem($0) },
            onResync: { [weak self] in
                await self?.loadPodsSnapshot(client: client, namespace: namespace, contextName: contextName, showLoading: false)
            }
        )
        startPodMetricsRefresh(client: client, namespace: namespace, contextName: contextName)
    }

    // MARK: - Deployment Loading

    func loadDeployments(client: KubernetesClient, namespace: String?) async {
        await loadDeploymentsSnapshot(client: client, namespace: namespace, showLoading: true)
        configureLiveWatch(
            apps.v1.Deployment.self,
            kind: .deployment,
            client: client,
            namespace: namespace,
            mapper: { Self.deploymentItem($0) },
            onResync: { [weak self] in
                await self?.loadDeploymentsSnapshot(client: client, namespace: namespace, showLoading: false)
            }
        )
    }

    // MARK: - Generic Namespaced Loading

    func loadNamespacedResources<R: KubernetesAPIResource & NamespacedResource & ListableResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        namespace: String?,
        mapper: @Sendable @escaping (R) -> ResourceItem
    ) async where R.List.Item == R {
        await loadNamespacedResourcesSnapshot(
            type,
            client: client,
            namespace: namespace,
            mapper: mapper,
            showLoading: true
        )
        configureLiveWatch(
            type,
            kind: kind,
            client: client,
            namespace: namespace,
            mapper: mapper,
            onResync: { [weak self] in
                await self?.loadNamespacedResourcesSnapshot(
                    type,
                    client: client,
                    namespace: namespace,
                    mapper: mapper,
                    showLoading: false
                )
            }
        )
    }

    // MARK: - Generic Cluster-Scoped Loading

    func loadClusterScopedResources<R: KubernetesAPIResource & ClusterScopedResource & ListableResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        mapper: @Sendable @escaping (R) -> ResourceItem
    ) async where R.List.Item == R {
        await loadClusterScopedResourcesSnapshot(
            type,
            client: client,
            mapper: mapper,
            showLoading: true
        )
        configureLiveWatchClusterScoped(
            type,
            kind: kind,
            client: client,
            mapper: mapper,
            onResync: { [weak self] in
                await self?.loadClusterScopedResourcesSnapshot(
                    type,
                    client: client,
                    mapper: mapper,
                    showLoading: false
                )
            }
        )
    }

    private func loadPodsSnapshot(client: KubernetesClient, namespace: String?, contextName: String?, showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            let service = KubernetesService(client: client, contextName: contextName)
            let namespaceKey = namespace ?? "*all*"
            let isSameNamespace = podUsageMetricsNamespaceKey == namespaceKey
            let cacheAge = podUsageMetricsFetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
            let shouldRefreshMetrics = showLoading || !isSameNamespace || cacheAge > 8

            let podList: core.v1.PodList
            let usageByPodID: [String: PodUsageMetricsSample]

            if shouldRefreshMetrics {
                async let podListTask = service.list(core.v1.Pod.self, in: namespace)
                async let usageTask: [String: PodUsageMetricsSample]? = try? service.fetchPodUsageMetrics(namespace: namespace)
                podList = try await podListTask

                if let freshUsage = await usageTask {
                    usageByPodID = freshUsage
                    podUsageMetricsCache = freshUsage
                    podUsageMetricsFetchedAt = Date()
                    podUsageMetricsNamespaceKey = namespaceKey
                } else {
                    usageByPodID = (isSameNamespace ? podUsageMetricsCache : [:])
                }
            } else {
                podList = try await service.list(core.v1.Pod.self, in: namespace)
                usageByPodID = podUsageMetricsCache
            }

            resources = podList.items.map { Self.podItem($0, usageMetrics: usageByPodID) }
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading {
            isLoading = false
        }
    }

    private func loadDeploymentsSnapshot(client: KubernetesClient, namespace: String?, showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.list(apps.v1.Deployment.self, in: namespace)
            resources = list.items.map { deploy in
                Self.deploymentItem(deploy)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading {
            isLoading = false
        }
    }

    private func loadNamespacedResourcesSnapshot<R: KubernetesAPIResource & NamespacedResource & ListableResource>(
        _ type: R.Type,
        client: KubernetesClient,
        namespace: String?,
        mapper: @Sendable @escaping (R) -> ResourceItem,
        showLoading: Bool
    ) async where R.List.Item == R {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.list(type, in: namespace)
            resources = list.items.map(mapper)
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading {
            isLoading = false
        }
    }

    private func loadClusterScopedResourcesSnapshot<R: KubernetesAPIResource & ClusterScopedResource & ListableResource>(
        _ type: R.Type,
        client: KubernetesClient,
        mapper: @Sendable @escaping (R) -> ResourceItem,
        showLoading: Bool
    ) async where R.List.Item == R {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            let service = KubernetesService(client: client)
            let list = try await service.listClusterScoped(type)
            resources = list.items.map(mapper)
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading {
            isLoading = false
        }
    }

    // MARK: - Watch

    private func configureLiveWatch<R: KubernetesAPIResource & NamespacedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        namespace: String?,
        mapper: @escaping @Sendable (R) -> ResourceItem,
        onResync: @escaping @MainActor () async -> Void
    ) {
        let context = LiveWatchContext(
            kind: kind,
            namespace: namespace,
            clientIdentity: ObjectIdentifier(client)
        )

        if liveWatchContext == context {
            resyncAction = onResync
            return
        }

        stopWatch()

        liveWatchContext = context
        resyncAction = onResync
        liveWatchStatus = .syncing
        let watcher = ResourceWatcher(client: client)
        self.watcher = watcher

        watchTask = Task { [weak self] in
            let stream = await watcher.watchMapped(type, kind: kind, in: namespace, mapper: mapper)
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleWatchChange(event)
            }
        }

        startFallbackResync()
        startWatchHealthPolling(for: kind)
    }

    private func configureLiveWatchClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        client: KubernetesClient,
        mapper: @escaping @Sendable (R) -> ResourceItem,
        onResync: @escaping @MainActor () async -> Void
    ) {
        let context = LiveWatchContext(
            kind: kind,
            namespace: nil,
            clientIdentity: ObjectIdentifier(client)
        )

        if liveWatchContext == context {
            resyncAction = onResync
            return
        }

        stopWatch()

        liveWatchContext = context
        resyncAction = onResync
        liveWatchStatus = .syncing
        let watcher = ResourceWatcher(client: client)
        self.watcher = watcher

        watchTask = Task { [weak self] in
            let stream = await watcher.watchMappedClusterScoped(type, kind: kind, mapper: mapper)
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleWatchChange(event)
            }
        }

        startFallbackResync()
        startWatchHealthPolling(for: kind)
    }

    func stopWatch() {
        watchTask?.cancel()
        watchTask = nil
        fallbackResyncTask?.cancel()
        fallbackResyncTask = nil
        watchHealthTask?.cancel()
        watchHealthTask = nil
        podMetricsTask?.cancel()
        podMetricsTask = nil

        if let watcher {
            Task {
                await watcher.stopAll()
            }
        }
        watcher = nil
        liveWatchContext = nil
        resyncAction = nil
        isPerformingResync = false
        liveWatchStatus = .off
    }

    /// Applies a single watch event to the in-memory list. This is what keeps
    /// the table live without re-fetching the whole resource list.
    private func handleWatchChange(_ event: MappedWatchEvent) {
        switch event.change {
        case .upsert(var item):
            if item.kind == .pod {
                item = decoratedWithPodMetrics(item)
            }
            if let index = resources.firstIndex(where: { $0.id == item.id }) {
                resources[index] = item
            } else {
                resources.append(item)
            }
            liveWatchStatus = .live(lastEventAt: Date())
        case .delete(let id):
            resources.removeAll { $0.id == id }
            liveWatchStatus = .live(lastEventAt: Date())
        case .error(let reason):
            liveWatchStatus = .recovering(lastEventAt: nil, reason: reason)
        }
    }

    /// Rare full-list resync as a safety net for events missed across watch
    /// reconnections. The heavy lifting is done by the incremental watch.
    private func startFallbackResync() {
        fallbackResyncTask?.cancel()
        fallbackResyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.resourceRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.performResyncIfNeeded()
            }
        }
    }

    private func startWatchHealthPolling(for kind: ResourceKind) {
        watchHealthTask?.cancel()
        watchHealthTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.watchHealthPollIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await self.refreshWatchHealth(kind: kind)
            }
        }
    }

    private func refreshWatchHealth(kind: ResourceKind) async {
        guard let watcher else {
            liveWatchStatus = .off
            return
        }

        guard let health = await watcher.watchHealth(kind: kind) else {
            liveWatchStatus = .syncing
            return
        }

        if health.isRecovering {
            liveWatchStatus = .recovering(lastEventAt: health.lastEventAt, reason: health.lastError)
            return
        }

        // Quiet streams are normal for slow-changing kinds; no staleness check.
        liveWatchStatus = .live(lastEventAt: health.lastEventAt)
    }

    private func performResyncIfNeeded() async {
        guard !isPerformingResync, let resyncAction else { return }
        isPerformingResync = true
        defer { isPerformingResync = false }
        await resyncAction()
    }

    // MARK: - Pod Metrics Refresh

    private func startPodMetricsRefresh(client: KubernetesClient, namespace: String?, contextName: String?) {
        podMetricsTask?.cancel()
        podMetricsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.podMetricsRefreshIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await self.refreshPodMetrics(client: client, namespace: namespace, contextName: contextName)
            }
        }
    }

    private func refreshPodMetrics(client: KubernetesClient, namespace: String?, contextName: String?) async {
        let service = KubernetesService(client: client, contextName: contextName)
        guard let usage = try? await service.fetchPodUsageMetrics(namespace: namespace) else { return }

        podUsageMetricsCache = usage
        podUsageMetricsFetchedAt = Date()
        podUsageMetricsNamespaceKey = namespace ?? "*all*"

        resources = resources.map { item in
            guard item.kind == .pod else { return item }
            return decoratedWithPodMetrics(item)
        }
    }

    private func decoratedWithPodMetrics(_ item: ResourceItem) -> ResourceItem {
        var item = item
        if let metric = podUsageMetricsCache[item.id] {
            item.extraColumns["cpu"] = Self.formatCPUUsage(metric.cpuUsageCores)
            item.extraColumns["memory"] = Self.formatMemoryUsage(bytes: metric.memoryUsageBytes)
            item.cpuCores = metric.cpuUsageCores
            item.memoryBytes = metric.memoryUsageBytes
        }
        return item
    }

    // MARK: - Delete

    func deleteResource(kind: ResourceKind, name: String, namespace: String?, client: KubernetesClient) async {
        setOperationRunning("Deleting \(kind.rawValue) \(name)…")
        let service = KubernetesService(client: client)
        do {
            switch kind {
            case .pod:
                try await service.delete(core.v1.Pod.self, name: name, in: namespace)
            case .deployment:
                try await service.delete(apps.v1.Deployment.self, name: name, in: namespace)
            case .statefulSet:
                try await service.delete(apps.v1.StatefulSet.self, name: name, in: namespace)
            case .daemonSet:
                try await service.delete(apps.v1.DaemonSet.self, name: name, in: namespace)
            case .job:
                try await service.delete(batch.v1.Job.self, name: name, in: namespace)
            case .cronJob:
                try await service.delete(batch.v1.CronJob.self, name: name, in: namespace)
            case .replicaSet:
                try await service.delete(apps.v1.ReplicaSet.self, name: name, in: namespace)
            case .service:
                try await service.delete(core.v1.Service.self, name: name, in: namespace)
            case .ingress:
                try await service.delete(networking.v1.Ingress.self, name: name, in: namespace)
            case .endpoint:
                try await service.delete(core.v1.Endpoints.self, name: name, in: namespace)
            case .horizontalPodAutoscaler:
                try await service.delete(autoscaling.v2.HorizontalPodAutoscaler.self, name: name, in: namespace)
            case .networkPolicy:
                try await service.delete(networking.v1.NetworkPolicy.self, name: name, in: namespace)
            case .configMap:
                try await service.delete(core.v1.ConfigMap.self, name: name, in: namespace)
            case .secret:
                try await service.delete(core.v1.Secret.self, name: name, in: namespace)
            case .persistentVolumeClaim:
                try await service.delete(core.v1.PersistentVolumeClaim.self, name: name, in: namespace)
            case .limitRange:
                try await service.delete(core.v1.LimitRange.self, name: name, in: namespace)
            case .resourceQuota:
                try await service.delete(core.v1.ResourceQuota.self, name: name, in: namespace)
            case .podDisruptionBudget:
                try await service.delete(policy.v1.PodDisruptionBudget.self, name: name, in: namespace)
            case .serviceAccount:
                try await service.delete(core.v1.ServiceAccount.self, name: name, in: namespace)
            case .role:
                try await service.delete(rbac.v1.Role.self, name: name, in: namespace)
            case .roleBinding:
                try await service.delete(rbac.v1.RoleBinding.self, name: name, in: namespace)
            case .event:
                try await service.delete(core.v1.Event.self, name: name, in: namespace)
            case .node:
                try await service.deleteClusterScoped(core.v1.Node.self, name: name)
            case .namespace:
                try await service.deleteClusterScoped(core.v1.Namespace.self, name: name)
            case .persistentVolume:
                try await service.deleteClusterScoped(core.v1.PersistentVolume.self, name: name)
            case .storageClass:
                try await service.deleteClusterScoped(storage.v1.StorageClass.self, name: name)
            case .clusterRole:
                try await service.deleteClusterScoped(rbac.v1.ClusterRole.self, name: name)
            case .clusterRoleBinding:
                try await service.deleteClusterScoped(rbac.v1.ClusterRoleBinding.self, name: name)
            }
            let resourceID = namespace.map { "\($0)/\(name)" } ?? name
            resources.removeAll { $0.id == resourceID }
            setOperationSuccess("Deleted \(kind.rawValue) \(name)")
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
            setOperationError("Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Scale

    func scaleResource(kind: ResourceKind, name: String, namespace: String?, replicas: Int, client: KubernetesClient) async {
        setOperationRunning("Scaling \(kind.rawValue) \(name) to \(replicas)…")
        let service = KubernetesService(client: client)
        do {
            switch kind {
            case .deployment:
                try await service.scaleDeployment(name: name, in: namespace, replicas: Int32(replicas))
            case .statefulSet:
                try await service.scaleStatefulSet(name: name, in: namespace, replicas: Int32(replicas))
            case .replicaSet:
                try await service.scaleReplicaSet(name: name, in: namespace, replicas: Int32(replicas))
            default:
                break
            }
            setOperationSuccess("Scaled \(kind.rawValue) \(name) to \(replicas)")
        } catch {
            scaleError = error.localizedDescription
            showScaleError = true
            setOperationError("Scale failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restart

    func restartResource(kind: ResourceKind, name: String, namespace: String?, client: KubernetesClient) async {
        setOperationRunning("Restarting \(kind.rawValue) \(name)…")
        let service = KubernetesService(client: client)
        do {
            switch kind {
            case .deployment:
                try await service.restartDeployment(name: name, in: namespace)
            case .statefulSet:
                try await service.restartStatefulSet(name: name, in: namespace)
            case .daemonSet:
                try await service.restartDaemonSet(name: name, in: namespace)
            default:
                break
            }
            setOperationSuccess("Restart requested for \(kind.rawValue) \(name)")
        } catch {
            restartError = error.localizedDescription
            showRestartError = true
            setOperationError("Restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Node Scheduling

    func setNodeSchedulable(name: String, unschedulable: Bool, client: KubernetesClient) async {
        let verb = unschedulable ? "Cordon" : "Uncordon"
        setOperationRunning("\(verb)ing node \(name)…")
        let service = KubernetesService(client: client)
        do {
            try await service.setNodeUnschedulable(name: name, unschedulable: unschedulable)
            setOperationSuccess("\(verb)ed node \(name)")
        } catch {
            setOperationError("\(verb) failed: \(error.localizedDescription)")
        }
    }

    func drainNode(name: String, client: KubernetesClient, contextName: String?) async {
        setOperationRunning("Draining node \(name)… (this can take a while)")
        let service = KubernetesService(client: client, contextName: contextName)
        do {
            _ = try await service.drainNode(name: name)
            setOperationSuccess("Drained node \(name)")
        } catch {
            setOperationError("Drain failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Rollout Undo

    func rolloutUndo(kind: ResourceKind, name: String, namespace: String?, client: KubernetesClient, contextName: String?) async {
        let resourceArgument: String
        switch kind {
        case .deployment:
            resourceArgument = "deployment/\(name)"
        case .statefulSet:
            resourceArgument = "statefulset/\(name)"
        case .daemonSet:
            resourceArgument = "daemonset/\(name)"
        default:
            return
        }

        setOperationRunning("Rolling back \(kind.rawValue) \(name)…")
        let service = KubernetesService(client: client, contextName: contextName)
        do {
            _ = try await service.rolloutUndo(resourceArgument: resourceArgument, in: namespace)
            setOperationSuccess("Rolled back \(kind.rawValue) \(name)")
        } catch {
            setOperationError("Rollback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Download YAML

    func fetchResourceYAML(kind: ResourceKind, name: String, namespace: String?, client: KubernetesClient) async throws -> String {
        let service = KubernetesService(client: client)

        switch kind {
        case .pod:
            let r = try await service.get(core.v1.Pod.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .deployment:
            let r = try await service.get(apps.v1.Deployment.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .statefulSet:
            let r = try await service.get(apps.v1.StatefulSet.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .daemonSet:
            let r = try await service.get(apps.v1.DaemonSet.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .job:
            let r = try await service.get(batch.v1.Job.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .cronJob:
            let r = try await service.get(batch.v1.CronJob.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .replicaSet:
            let r = try await service.get(apps.v1.ReplicaSet.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .service:
            let r = try await service.get(core.v1.Service.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .ingress:
            let r = try await service.get(networking.v1.Ingress.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .configMap:
            let r = try await service.get(core.v1.ConfigMap.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .secret:
            let r = try await service.get(core.v1.Secret.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .persistentVolumeClaim:
            let r = try await service.get(core.v1.PersistentVolumeClaim.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .serviceAccount:
            let r = try await service.get(core.v1.ServiceAccount.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .endpoint:
            let r = try await service.get(core.v1.Endpoints.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .horizontalPodAutoscaler:
            let r = try await service.get(autoscaling.v2.HorizontalPodAutoscaler.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .networkPolicy:
            let r = try await service.get(networking.v1.NetworkPolicy.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .limitRange:
            let r = try await service.get(core.v1.LimitRange.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .resourceQuota:
            let r = try await service.get(core.v1.ResourceQuota.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .podDisruptionBudget:
            let r = try await service.get(policy.v1.PodDisruptionBudget.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .role:
            let r = try await service.get(rbac.v1.Role.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .roleBinding:
            let r = try await service.get(rbac.v1.RoleBinding.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .event:
            let r = try await service.get(core.v1.Event.self, name: name, in: namespace)
            return try await service.getYAML(r)
        case .node:
            let r = try await service.getClusterScoped(core.v1.Node.self, name: name)
            return try await service.getYAML(r)
        case .namespace:
            let r = try await service.getClusterScoped(core.v1.Namespace.self, name: name)
            return try await service.getYAML(r)
        case .persistentVolume:
            let r = try await service.getClusterScoped(core.v1.PersistentVolume.self, name: name)
            return try await service.getYAML(r)
        case .storageClass:
            let r = try await service.getClusterScoped(storage.v1.StorageClass.self, name: name)
            return try await service.getYAML(r)
        case .clusterRole:
            let r = try await service.getClusterScoped(rbac.v1.ClusterRole.self, name: name)
            return try await service.getYAML(r)
        case .clusterRoleBinding:
            let r = try await service.getClusterScoped(rbac.v1.ClusterRoleBinding.self, name: name)
            return try await service.getYAML(r)
        }
    }

    func downloadResourceYAML(kind: ResourceKind, name: String, namespace: String?, client: KubernetesClient) async {
        setOperationRunning("Preparing YAML for \(kind.rawValue) \(name)…")
        do {
            let yaml = try await fetchResourceYAML(kind: kind, name: name, namespace: namespace, client: client)
            let didSave = presentSavePanel(yaml: yaml, fileName: "\(name).yaml")
            if didSave {
                setOperationSuccess("Downloaded YAML for \(kind.rawValue) \(name)")
            } else {
                clearOperationState()
            }
        } catch {
            deleteError = "Failed to download YAML: \(error.localizedDescription)"
            showDeleteError = true
            setOperationError("YAML download failed: \(error.localizedDescription)")
        }
    }

    private func presentSavePanel(yaml: String, fileName: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType.yaml]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            deleteError = "Failed to save file: \(error.localizedDescription)"
            showDeleteError = true
            return false
        }
    }

    // MARK: - Operation State

    func clearOperationState() {
        operationResetTask?.cancel()
        operationResetTask = nil
        operationState = .idle
    }

    private func setOperationRunning(_ message: String) {
        operationResetTask?.cancel()
        operationResetTask = nil
        operationState = .running(message)
    }

    private func setOperationSuccess(_ message: String) {
        operationResetTask?.cancel()
        operationState = .success(message)

        operationResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if case .success = self.operationState {
                    self.operationState = .idle
                }
            }
        }
    }

    private func setOperationError(_ message: String) {
        operationResetTask?.cancel()
        operationState = .error(message)
    }

    // MARK: - Resource Mappers

    /// Base pod mapping without usage metrics — also used by the watch stream,
    /// where metrics are merged in afterwards from the MainActor cache.
    nonisolated static func basePodItem(_ pod: core.v1.Pod) -> ResourceItem {
        let restarts = PodStatusFormatter.restartCount(for: pod)
        let readiness = PodStatusFormatter.readySummary(for: pod)
        let status = PodStatusFormatter.displayStatus(for: pod)
        let namespace = pod.metadata?.namespace
        let name = pod.name ?? ""
        let resourceID = "\(namespace ?? "")/\(name)"

        var extra: [String: String] = [:]
        extra["ready"] = "\(readiness.ready)/\(readiness.total)"
        extra["restarts"] = "\(restarts)"
        extra["node"] = pod.spec?.nodeName ?? ""
        extra["ip"] = pod.status?.podIP ?? ""
        extra["container"] = pod.spec?.containers.first?.name ?? ""
        extra["portNumbers"] = (pod.spec?.containers ?? [])
            .flatMap { $0.ports ?? [] }
            .map { String($0.containerPort) }
            .joined(separator: ",")
        extra["cpu"] = "-"
        extra["memory"] = "-"
        extra["containers"] = "\(readiness.ready)/\(readiness.total)"
        extra["containerReady"] = "\(readiness.ready)"
        extra["containerTotal"] = "\(readiness.total)"

        return ResourceItem(
            id: resourceID,
            name: name,
            namespace: namespace,
            status: status,
            age: pod.metadata?.creationTimestamp,
            labels: pod.metadata?.labels ?? [:],
            annotations: pod.metadata?.annotations ?? [:],
            kind: .pod,
            extraColumns: extra
        )
    }

    private nonisolated static func podItem(
        _ pod: core.v1.Pod,
        usageMetrics: [String: PodUsageMetricsSample]
    ) -> ResourceItem {
        var item = basePodItem(pod)
        if let metric = usageMetrics[item.id] {
            item.extraColumns["cpu"] = formatCPUUsage(metric.cpuUsageCores)
            item.extraColumns["memory"] = formatMemoryUsage(bytes: metric.memoryUsageBytes)
            item.cpuCores = metric.cpuUsageCores
            item.memoryBytes = metric.memoryUsageBytes
        }
        return item
    }

    private nonisolated static func formatCPUUsage(_ cores: Double) -> String {
        String(format: "%.3f", cores)
    }

    private nonisolated static func formatMemoryUsage(bytes: Double) -> String {
        guard bytes > 0 else { return "0B" }

        let gib = bytes / (1024 * 1024 * 1024)
        if gib >= 1 {
            return String(format: "%.1fGiB", gib)
        }

        let mib = bytes / (1024 * 1024)
        if mib >= 1 {
            return String(format: "%.1fMiB", mib)
        }

        let kib = bytes / 1024
        if kib >= 1 {
            return String(format: "%.1fKiB", kib)
        }

        return String(format: "%.0fB", bytes)
    }

    nonisolated static func deploymentItem(_ deploy: apps.v1.Deployment) -> ResourceItem {
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
