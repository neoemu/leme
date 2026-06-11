import Foundation
import SwiftkubeClient
import SwiftkubeModel
import Yams

// MARK: - ClusterManagerError

enum ClusterManagerError: LocalizedError, Sendable {
    case kubeconfigNotFound(path: String)
    case kubeconfigParseError(String)
    case contextNotFound(String)
    case clusterNotFound(String)
    case userNotFound(String)
    case clientCreationFailed(String)
    case notConnected(String)
    case connectionTimedOut(context: String, seconds: TimeInterval)
    case connectionInProgress(String)

    var errorDescription: String? {
        switch self {
        case .kubeconfigNotFound(let path):
            return "Kubeconfig file not found at: \(path)"
        case .kubeconfigParseError(let detail):
            return "Failed to parse kubeconfig: \(detail)"
        case .contextNotFound(let name):
            return "Context '\(name)' not found in kubeconfig"
        case .clusterNotFound(let name):
            return "Cluster '\(name)' not found in kubeconfig"
        case .userNotFound(let name):
            return "User '\(name)' not found in kubeconfig"
        case .clientCreationFailed(let detail):
            return "Failed to create Kubernetes client: \(detail)"
        case .notConnected(let context):
            return "Not connected to cluster context '\(context)'"
        case .connectionTimedOut(let context, let seconds):
            return "Connection to '\(context)' timed out after \(Int(seconds))s. Check VPN/network and cluster availability."
        case .connectionInProgress(let context):
            return "A connection attempt for '\(context)' is already in progress"
        }
    }
}

// MARK: - KubeconfigData

/// Parsed representation of a kubeconfig YAML file using Yams.
/// This is separate from SwiftkubeClient's KubeConfig to allow manual YAML parsing.
private struct KubeconfigData: Sendable {
    struct ContextEntry: Sendable {
        let name: String
        let clusterName: String
        let userName: String
        let namespace: String?
    }

    struct ClusterEntry: Sendable {
        let name: String
        let server: String
    }

    struct UserEntry: Sendable {
        let name: String
    }

    let currentContext: String?
    let contexts: [ContextEntry]
    let clusters: [ClusterEntry]
    let users: [UserEntry]
}

// MARK: - ClusterManager

actor ClusterManager {

    // MARK: - Properties

    private var activeClients: [UUID: KubernetesClient] = [:]
    private var connectingIDs: Set<UUID> = []
    private var cachedKubeConfig: KubeConfig?

    // MARK: - Kubeconfig Loading

    /// Reads and parses the kubeconfig file at the given path using Yams.
    /// Returns an array of ClusterConnection objects representing each context.
    func loadContexts(from path: String = Constants.defaultKubeconfigPath) throws -> [ClusterConnection] {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw ClusterManagerError.kubeconfigNotFound(path: expandedPath)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let parsed = try parseKubeconfig(yaml: contents)

        // Also cache the SwiftkubeClient KubeConfig for later client creation
        cachedKubeConfig = try KubeConfig.from(config: contents)

        return buildClusterConnections(from: parsed)
    }

    /// Parses the raw YAML kubeconfig string using Yams into our internal representation.
    private func parseKubeconfig(yaml: String) throws -> KubeconfigData {
        guard let node = try Yams.compose(yaml: yaml),
              let mapping = node.mapping else {
            throw ClusterManagerError.kubeconfigParseError("Invalid YAML structure")
        }

        let currentContext = mapping[Yams.Node("current-context")]?.string

        // Parse contexts
        var contexts: [KubeconfigData.ContextEntry] = []
        if let contextsNode = mapping[Yams.Node("contexts")]?.sequence {
            for contextNode in contextsNode {
                guard let contextMapping = contextNode.mapping,
                      let name = contextMapping[Yams.Node("name")]?.string,
                      let contextDetail = contextMapping[Yams.Node("context")]?.mapping,
                      let clusterName = contextDetail[Yams.Node("cluster")]?.string,
                      let userName = contextDetail[Yams.Node("user")]?.string else {
                    continue
                }
                let namespace = contextDetail[Yams.Node("namespace")]?.string
                contexts.append(KubeconfigData.ContextEntry(
                    name: name,
                    clusterName: clusterName,
                    userName: userName,
                    namespace: namespace
                ))
            }
        }

        // Parse clusters
        var clusters: [KubeconfigData.ClusterEntry] = []
        if let clustersNode = mapping[Yams.Node("clusters")]?.sequence {
            for clusterNode in clustersNode {
                guard let clusterMapping = clusterNode.mapping,
                      let name = clusterMapping[Yams.Node("name")]?.string,
                      let clusterDetail = clusterMapping[Yams.Node("cluster")]?.mapping,
                      let server = clusterDetail[Yams.Node("server")]?.string else {
                    continue
                }
                clusters.append(KubeconfigData.ClusterEntry(name: name, server: server))
            }
        }

        // Parse users
        var users: [KubeconfigData.UserEntry] = []
        if let usersNode = mapping[Yams.Node("users")]?.sequence {
            for userNode in usersNode {
                guard let userMapping = userNode.mapping,
                      let name = userMapping[Yams.Node("name")]?.string else {
                    continue
                }
                users.append(KubeconfigData.UserEntry(name: name))
            }
        }

        return KubeconfigData(
            currentContext: currentContext,
            contexts: contexts,
            clusters: clusters,
            users: users
        )
    }

    /// Builds ClusterConnection objects from parsed kubeconfig data.
    private func buildClusterConnections(from data: KubeconfigData) -> [ClusterConnection] {
        let clustersByName = Dictionary(uniqueKeysWithValues: data.clusters.map { ($0.name, $0) })

        return data.contexts.map { context in
            let cluster = clustersByName[context.clusterName]
            return ClusterConnection(
                id: UUID(stableFrom: context.name),
                contextName: context.name,
                clusterName: context.clusterName,
                clusterURL: cluster?.server ?? "",
                userName: context.userName,
                status: .disconnected,
                currentNamespace: context.namespace
            )
        }
    }

    // MARK: - Connection Management

    /// Ensures PATH includes common binary directories so exec-based auth
    /// plugins (kubelogin, gcloud, aws-iam-authenticator, etc.) can be found.
    private func ensurePATH() {
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let missingPaths = extraPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            let newPath = (missingPaths + [currentPath]).joined(separator: ":")
            setenv("PATH", newPath, 1)
        }
    }

    /// Connects to a cluster using the specified context name.
    /// Creates a KubernetesClient and fetches available namespaces.
    func connect(
        connection: ClusterConnection,
        kubeConfigPath: String = Constants.defaultKubeconfigPath
    ) async throws -> ClusterConnection {
        // Reject concurrent attempts for the same cluster: overlapping connects
        // would overwrite each other's clients in activeClients, deallocating
        // a KubernetesClient that was never shut down (crashes in debug).
        guard !connectingIDs.contains(connection.id) else {
            throw ClusterManagerError.connectionInProgress(connection.contextName)
        }
        connectingIDs.insert(connection.id)
        defer { connectingIDs.remove(connection.id) }

        var updated = connection
        updated.status = .connecting

        // Ensure exec-based auth plugins can be resolved
        ensurePATH()

        do {
            // Load kubeconfig if not cached
            if cachedKubeConfig == nil {
                let expandedPath = (kubeConfigPath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expandedPath)
                let contents = try String(contentsOf: url, encoding: .utf8)
                cachedKubeConfig = try KubeConfig.from(config: contents)
            }

            guard let kubeConfig = cachedKubeConfig else {
                throw ClusterManagerError.kubeconfigParseError("No kubeconfig available")
            }

            // Create a KubernetesClient for the specific context
            guard let client = KubernetesClient(kubeConfig: kubeConfig, contextName: connection.contextName) else {
                throw ClusterManagerError.clientCreationFailed(
                    "Could not create client for context '\(connection.contextName)'"
                )
            }

            // Fetch namespaces as a connectivity probe, bounded by a timeout so
            // unreachable clusters don't hang in "connecting" indefinitely.
            let namespaceList: core.v1.NamespaceList
            do {
                namespaceList = try await Self.withTimeout(
                    seconds: Constants.clusterConnectTimeout,
                    onTimeout: ClusterManagerError.connectionTimedOut(
                        context: connection.contextName,
                        seconds: Constants.clusterConnectTimeout
                    )
                ) {
                    try await client.namespaces.list()
                }
            } catch {
                try? await client.shutdown()
                throw error
            }

            // Store the client only after the probe succeeds. Shut down any
            // previous client for this cluster before replacing it — silently
            // dropping the reference would deallocate it without shutdown.
            if let previous = activeClients.removeValue(forKey: connection.id) {
                try? await previous.shutdown()
            }
            activeClients[connection.id] = client

            let namespaces = namespaceList.items.compactMap { $0.name }

            updated.namespaces = namespaces.sorted()
            updated.status = .connected
            updated.errorMessage = nil

            // Set default namespace if not already set
            if updated.currentNamespace == nil {
                updated.currentNamespace = namespaces.contains("default") ? "default" : namespaces.first
            }

            return updated
        } catch let error as ClusterManagerError {
            updated.status = .error
            updated.errorMessage = error.localizedDescription
            throw error
        } catch {
            updated.status = .error
            updated.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Disconnects from a cluster, shutting down its KubernetesClient.
    func disconnect(connectionID: UUID) async -> ClusterConnection? {
        guard let client = activeClients.removeValue(forKey: connectionID) else {
            return nil
        }

        try? await client.shutdown()
        return nil
    }

    /// Retrieves the active KubernetesClient for a given connection ID.
    func client(for connectionID: UUID) throws -> KubernetesClient {
        guard let client = activeClients[connectionID] else {
            throw ClusterManagerError.notConnected("No active client for connection")
        }
        return client
    }

    /// Refreshes the namespace list for a connected cluster.
    func refreshNamespaces(for connectionID: UUID) async throws -> [String] {
        let client = try client(for: connectionID)
        let namespaceList = try await client.namespaces.list()
        return namespaceList.items.compactMap { $0.name }.sorted()
    }

    /// Disconnects all active clients and cleans up resources.
    func disconnectAll() async {
        for (id, client) in activeClients {
            try? await client.shutdown()
            activeClients.removeValue(forKey: id)
        }
    }

    /// Invalidates the cached kubeconfig, forcing a reload on next use.
    func invalidateCache() {
        cachedKubeConfig = nil
    }

    /// Races an async operation against a deadline, throwing `onTimeout` if it loses.
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        onTimeout: ClusterManagerError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw onTimeout
            }
            guard let result = try await group.next() else {
                throw onTimeout
            }
            group.cancelAll()
            return result
        }
    }
}
