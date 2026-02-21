import Foundation
import SwiftkubeClient
import SwiftkubeModel

// MARK: - ResourceWatchEvent

/// Represents a watch event for a Kubernetes resource with type-erased resource data.
struct ResourceWatchEvent: Sendable {
    enum EventType: String, Sendable {
        case added
        case modified
        case deleted
        case error
    }

    let type: EventType
    let resourceName: String
    let resourceNamespace: String?
    let resourceVersion: String?
    let resourceKind: ResourceKind

    init(type: EventType, resourceName: String, resourceNamespace: String?, resourceVersion: String?, resourceKind: ResourceKind) {
        self.type = type
        self.resourceName = resourceName
        self.resourceNamespace = resourceNamespace
        self.resourceVersion = resourceVersion
        self.resourceKind = resourceKind
    }
}

// MARK: - ResourceWatcher

/// Actor that manages watch tasks per resource kind.
/// Uses SwiftkubeClient's watch API to observe changes to Kubernetes resources,
/// implementing exponential backoff for reconnection. Notifies consumers via
/// AsyncStream of ResourceWatchEvent.
actor ResourceWatcher {

    // MARK: - Properties

    private var watchTasks: [ResourceKind: Task<Void, Never>] = [:]
    private var continuations: [ResourceKind: AsyncStream<ResourceWatchEvent>.Continuation] = [:]
    private let client: KubernetesClient

    // MARK: - Initialization

    init(client: KubernetesClient) {
        self.client = client
    }

    // MARK: - Watch Management

    /// Starts watching the specified resource kind in the given namespace.
    /// Returns an AsyncStream that yields ResourceWatchEvent values.
    /// If a watch is already active for this kind, the existing one is cancelled first.
    func watch(
        kind: ResourceKind,
        in namespace: String? = nil
    ) -> AsyncStream<ResourceWatchEvent> {
        // Cancel any existing watch for this kind
        stopWatching(kind: kind)

        let (stream, continuation) = AsyncStream<ResourceWatchEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1000)
        )
        continuations[kind] = continuation

        let retryStrategy = RetryStrategy(
            policy: .always,
            backoff: .exponential(
                maximumDelay: Constants.watchReconnectMaxDelay,
                multiplier: 2.0
            ),
            initialDelay: Constants.watchReconnectBaseDelay,
            jitter: 0.2
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runWatch(kind: kind, namespace: namespace, retryStrategy: retryStrategy)
        }

        watchTasks[kind] = task
        return stream
    }

    /// Stops watching the specified resource kind.
    func stopWatching(kind: ResourceKind) {
        watchTasks[kind]?.cancel()
        watchTasks.removeValue(forKey: kind)
        continuations[kind]?.finish()
        continuations.removeValue(forKey: kind)
    }

    /// Stops all active watches.
    func stopAll() {
        for kind in watchTasks.keys {
            stopWatching(kind: kind)
        }
    }

    /// Returns whether a watch is active for the given resource kind.
    func isWatching(kind: ResourceKind) -> Bool {
        watchTasks[kind] != nil
    }

    // MARK: - Private Watch Implementation

    private func runWatch(
        kind: ResourceKind,
        namespace: String?,
        retryStrategy: RetryStrategy
    ) async {
        do {
            switch kind {
            case .pod:
                try await watchNamespaced(core.v1.Pod.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .deployment:
                try await watchNamespaced(apps.v1.Deployment.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .statefulSet:
                try await watchNamespaced(apps.v1.StatefulSet.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .daemonSet:
                try await watchNamespaced(apps.v1.DaemonSet.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .replicaSet:
                try await watchNamespaced(apps.v1.ReplicaSet.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .job:
                try await watchNamespaced(batch.v1.Job.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .cronJob:
                try await watchNamespaced(batch.v1.CronJob.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .service:
                try await watchNamespaced(core.v1.Service.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .ingress:
                try await watchNamespaced(networking.v1.Ingress.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .endpoint:
                try await watchNamespaced(core.v1.Endpoints.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .networkPolicy:
                try await watchNamespaced(networking.v1.NetworkPolicy.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .configMap:
                try await watchNamespaced(core.v1.ConfigMap.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .secret:
                try await watchNamespaced(core.v1.Secret.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .persistentVolumeClaim:
                try await watchNamespaced(core.v1.PersistentVolumeClaim.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .serviceAccount:
                try await watchNamespaced(core.v1.ServiceAccount.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .event:
                try await watchNamespaced(core.v1.Event.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .role:
                try await watchNamespaced(rbac.v1.Role.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .roleBinding:
                try await watchNamespaced(rbac.v1.RoleBinding.self, kind: kind, namespace: namespace, retryStrategy: retryStrategy)
            case .node:
                try await watchClusterScoped(core.v1.Node.self, kind: kind, retryStrategy: retryStrategy)
            case .namespace:
                try await watchClusterScoped(core.v1.Namespace.self, kind: kind, retryStrategy: retryStrategy)
            case .persistentVolume:
                try await watchClusterScoped(core.v1.PersistentVolume.self, kind: kind, retryStrategy: retryStrategy)
            case .storageClass:
                try await watchClusterScoped(storage.v1.StorageClass.self, kind: kind, retryStrategy: retryStrategy)
            case .clusterRole:
                try await watchClusterScoped(rbac.v1.ClusterRole.self, kind: kind, retryStrategy: retryStrategy)
            case .clusterRoleBinding:
                try await watchClusterScoped(rbac.v1.ClusterRoleBinding.self, kind: kind, retryStrategy: retryStrategy)
            }
        } catch {
            // If watching fails entirely, emit an error event and clean up
            if !Task.isCancelled {
                let errorEvent = ResourceWatchEvent(
                    type: .error,
                    resourceName: error.localizedDescription,
                    resourceNamespace: nil,
                    resourceVersion: nil,
                    resourceKind: kind
                )
                continuations[kind]?.yield(errorEvent)
            }
        }
    }

    /// Watches a namespaced resource type and emits events through the continuation.
    private func watchNamespaced<R: KubernetesAPIResource & NamespacedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        namespace: String?,
        retryStrategy: RetryStrategy
    ) async throws {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: type)
        let watchTask = try await scopedClient.watch(in: selector, retryStrategy: retryStrategy)
        let stream = await watchTask.start()

        for try await event in stream {
            guard !Task.isCancelled else { break }

            let watchEvent = ResourceWatchEvent(
                type: mapEventType(event.type),
                resourceName: event.resource.name ?? "unknown",
                resourceNamespace: event.resource.metadata?.namespace,
                resourceVersion: event.resource.metadata?.resourceVersion,
                resourceKind: kind
            )
            continuations[kind]?.yield(watchEvent)
        }
    }

    /// Watches a cluster-scoped resource type and emits events through the continuation.
    private func watchClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        retryStrategy: RetryStrategy
    ) async throws {
        let scopedClient = client.clusterScoped(for: type)
        let watchTask = try await scopedClient.watch(retryStrategy: retryStrategy)
        let stream = await watchTask.start()

        for try await event in stream {
            guard !Task.isCancelled else { break }

            let watchEvent = ResourceWatchEvent(
                type: mapEventType(event.type),
                resourceName: event.resource.name ?? "unknown",
                resourceNamespace: nil,
                resourceVersion: event.resource.metadata?.resourceVersion,
                resourceKind: kind
            )
            continuations[kind]?.yield(watchEvent)
        }
    }

    /// Maps SwiftkubeClient's EventType to our ResourceWatchEvent.EventType.
    private func mapEventType(_ type: EventType) -> ResourceWatchEvent.EventType {
        switch type {
        case .added: return .added
        case .modified: return .modified
        case .deleted: return .deleted
        case .error: return .error
        }
    }
}
