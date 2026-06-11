import Foundation
import SwiftkubeClient
import SwiftkubeModel

// MARK: - MappedWatchEvent

/// A watch event already mapped to the UI's row model, so consumers can apply
/// it incrementally to a resource list without re-fetching anything.
struct MappedWatchEvent: Sendable {
    enum Change: Sendable {
        case upsert(ResourceItem)
        case delete(id: String)
        case error(String)
    }

    let change: Change
}

struct ResourceWatchHealth: Sendable, Equatable {
    var lastEventAt: Date?
    var lastError: String?
    var isRecovering: Bool

    static let initial = ResourceWatchHealth(
        lastEventAt: nil,
        lastError: nil,
        isRecovering: true
    )
}

// MARK: - ResourceWatcher

/// Actor that manages watch tasks per resource kind.
/// Uses SwiftkubeClient's watch API with automatic reconnection and yields
/// `MappedWatchEvent`s through an AsyncStream so the UI can apply changes
/// incrementally.
actor ResourceWatcher {

    // MARK: - Properties

    private var watchTasks: [ResourceKind: Task<Void, Never>] = [:]
    private var continuations: [ResourceKind: AsyncStream<MappedWatchEvent>.Continuation] = [:]
    private var healthByKind: [ResourceKind: ResourceWatchHealth] = [:]
    private let client: KubernetesClient

    private static let retryStrategy = RetryStrategy(
        policy: .always,
        backoff: .exponential(
            maximumDelay: Constants.watchReconnectMaxDelay,
            multiplier: 2.0
        ),
        initialDelay: Constants.watchReconnectBaseDelay,
        jitter: 0.2
    )

    // MARK: - Initialization

    init(client: KubernetesClient) {
        self.client = client
    }

    /// Minimal mapper for aggregate views that only use watch events as a
    /// change signal and reload their own data.
    nonisolated static func signalMapper<R: KubernetesAPIResource>(kind: ResourceKind) -> @Sendable (R) -> ResourceItem {
        { resource in
            let name = resource.name ?? ""
            let namespace = resource.metadata?.namespace
            return ResourceItem(
                id: namespace.map { "\($0)/\(name)" } ?? name,
                name: name,
                namespace: namespace,
                status: "",
                age: nil,
                labels: [:],
                annotations: [:],
                kind: kind
            )
        }
    }

    // MARK: - Watch Management

    /// Starts watching a namespaced resource type, yielding mapped events.
    /// If a watch is already active for this kind, it is cancelled first.
    func watchMapped<R: KubernetesAPIResource & NamespacedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        in namespace: String?,
        mapper: @escaping @Sendable (R) -> ResourceItem
    ) -> AsyncStream<MappedWatchEvent> {
        let (stream, _) = prepareStream(for: kind)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
                let scopedClient = self.client.namespaceScoped(for: type)
                let watchTask = try await scopedClient.watch(in: selector, retryStrategy: Self.retryStrategy)
                let eventStream = await watchTask.start()
                try await self.consume(eventStream, kind: kind, mapper: mapper)
            } catch {
                await self.emitStreamFailure(kind: kind, error: error)
            }
        }

        watchTasks[kind] = task
        return stream
    }

    /// Starts watching a cluster-scoped resource type, yielding mapped events.
    func watchMappedClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource>(
        _ type: R.Type,
        kind: ResourceKind,
        mapper: @escaping @Sendable (R) -> ResourceItem
    ) -> AsyncStream<MappedWatchEvent> {
        let (stream, _) = prepareStream(for: kind)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let scopedClient = self.client.clusterScoped(for: type)
                let watchTask = try await scopedClient.watch(retryStrategy: Self.retryStrategy)
                let eventStream = await watchTask.start()
                try await self.consume(eventStream, kind: kind, mapper: mapper)
            } catch {
                await self.emitStreamFailure(kind: kind, error: error)
            }
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
        healthByKind.removeValue(forKey: kind)
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

    func watchHealth(kind: ResourceKind) -> ResourceWatchHealth? {
        healthByKind[kind]
    }

    // MARK: - Private

    private func prepareStream(for kind: ResourceKind) -> (AsyncStream<MappedWatchEvent>, AsyncStream<MappedWatchEvent>.Continuation) {
        stopWatching(kind: kind)
        healthByKind[kind] = .initial

        let (stream, continuation) = AsyncStream<MappedWatchEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1000)
        )
        continuations[kind] = continuation
        return (stream, continuation)
    }

    private func consume<R: KubernetesAPIResource>(
        _ eventStream: AsyncThrowingStream<WatchEvent<R>, Error>,
        kind: ResourceKind,
        mapper: @escaping @Sendable (R) -> ResourceItem
    ) async throws {
        for try await event in eventStream {
            guard !Task.isCancelled else { break }

            switch event.type {
            case .added, .modified:
                updateHealthForSuccess(kind: kind)
                continuations[kind]?.yield(MappedWatchEvent(change: .upsert(mapper(event.resource))))
            case .deleted:
                updateHealthForSuccess(kind: kind)
                continuations[kind]?.yield(MappedWatchEvent(change: .delete(id: mapper(event.resource).id)))
            case .error:
                updateHealthForError(kind: kind, message: "Watch stream returned an API error event.")
                continuations[kind]?.yield(MappedWatchEvent(change: .error("Watch stream returned an API error event.")))
            }
        }
    }

    private func emitStreamFailure(kind: ResourceKind, error: Error) {
        guard !Task.isCancelled else { return }
        updateHealthForError(kind: kind, message: error.localizedDescription)
        continuations[kind]?.yield(MappedWatchEvent(change: .error(error.localizedDescription)))
    }

    private func updateHealthForSuccess(kind: ResourceKind) {
        var health = healthByKind[kind] ?? .initial
        health.lastEventAt = Date()
        health.isRecovering = false
        healthByKind[kind] = health
    }

    private func updateHealthForError(kind: ResourceKind, message: String) {
        var health = healthByKind[kind] ?? .initial
        health.lastError = message
        health.isRecovering = true
        healthByKind[kind] = health
    }
}
