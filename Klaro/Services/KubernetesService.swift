import Foundation
import SwiftkubeClient
import SwiftkubeModel
import Yams

// MARK: - KubernetesServiceError

enum KubernetesServiceError: LocalizedError, Sendable {
    case resourceNotFound(kind: String, name: String)
    case yamlSerializationFailed(String)
    case yamlDeserializationFailed(String)
    case unsupportedResourceKind(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let kind, let name):
            return "\(kind) '\(name)' not found"
        case .yamlSerializationFailed(let detail):
            return "Failed to serialize resource to YAML: \(detail)"
        case .yamlDeserializationFailed(let detail):
            return "Failed to deserialize YAML: \(detail)"
        case .unsupportedResourceKind(let kind):
            return "Unsupported resource kind: \(kind)"
        case .operationFailed(let detail):
            return "Operation failed: \(detail)"
        }
    }
}

// MARK: - KubernetesService

/// A facade actor that wraps a KubernetesClient instance and provides
/// typed methods for listing, getting, watching, deleting, and YAML operations
/// on Kubernetes resources.
actor KubernetesService {

    // MARK: - Properties

    private let client: KubernetesClient

    // MARK: - Initialization

    init(client: KubernetesClient) {
        self.client = client
    }

    // MARK: - Namespaced List Operations

    /// Lists namespaced resources of the given type in the specified namespace.
    func list<R: KubernetesAPIResource & NamespacedResource & ListableResource>(
        _ type: R.Type,
        in namespace: String? = nil
    ) async throws -> R.List {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: type)
        return try await scopedClient.list(in: selector)
    }

    /// Lists cluster-scoped resources of the given type.
    func listClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ListableResource>(
        _ type: R.Type
    ) async throws -> R.List {
        let scopedClient = client.clusterScoped(for: type)
        return try await scopedClient.list()
    }

    // MARK: - Get Operations

    /// Gets a single namespaced resource by name.
    func get<R: KubernetesAPIResource & NamespacedResource & ReadableResource>(
        _ type: R.Type,
        name: String,
        in namespace: String? = nil
    ) async throws -> R {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: type)
        return try await scopedClient.get(in: selector, name: name)
    }

    /// Gets a single cluster-scoped resource by name.
    func getClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource>(
        _ type: R.Type,
        name: String
    ) async throws -> R {
        let scopedClient = client.clusterScoped(for: type)
        return try await scopedClient.get(name: name)
    }

    // MARK: - Watch Operations

    /// Watches namespaced resources, returning a SwiftkubeClientTask that can be started.
    func watch<R: KubernetesAPIResource & NamespacedResource & ReadableResource>(
        _ type: R.Type,
        in namespace: String? = nil,
        retryStrategy: RetryStrategy = RetryStrategy(
            policy: .maxAttempts(10),
            backoff: .exponential(maximumDelay: 30.0, multiplier: 2.0),
            initialDelay: 1.0,
            jitter: 0.2
        )
    ) async throws -> SwiftkubeClientTask<WatchEvent<R>> {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: type)
        return try await scopedClient.watch(in: selector, retryStrategy: retryStrategy)
    }

    /// Watches cluster-scoped resources, returning a SwiftkubeClientTask that can be started.
    func watchClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource>(
        _ type: R.Type,
        retryStrategy: RetryStrategy = RetryStrategy(
            policy: .maxAttempts(10),
            backoff: .exponential(maximumDelay: 30.0, multiplier: 2.0),
            initialDelay: 1.0,
            jitter: 0.2
        )
    ) async throws -> SwiftkubeClientTask<WatchEvent<R>> {
        let scopedClient = client.clusterScoped(for: type)
        return try await scopedClient.watch(retryStrategy: retryStrategy)
    }

    // MARK: - Delete Operations

    /// Deletes a namespaced resource by name.
    func delete<R: KubernetesAPIResource & NamespacedResource & DeletableResource>(
        _ type: R.Type,
        name: String,
        in namespace: String? = nil
    ) async throws {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: type)
        try await scopedClient.delete(inNamespace: selector, name: name)
    }

    /// Deletes a cluster-scoped resource by name.
    func deleteClusterScoped<R: KubernetesAPIResource & ClusterScopedResource & DeletableResource>(
        _ type: R.Type,
        name: String
    ) async throws {
        let scopedClient = client.clusterScoped(for: type)
        try await scopedClient.delete(name: name)
    }

    // MARK: - Create / Update Operations

    /// Creates a namespaced resource.
    func create<R: KubernetesAPIResource & NamespacedResource & CreatableResource>(
        _ resource: R,
        in namespace: String? = nil
    ) async throws -> R {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: R.self)
        return try await scopedClient.create(inNamespace: selector, resource)
    }

    /// Updates a namespaced resource.
    func update<R: KubernetesAPIResource & NamespacedResource & ReplaceableResource>(
        _ resource: R,
        in namespace: String? = nil
    ) async throws -> R {
        let selector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        let scopedClient = client.namespaceScoped(for: R.self)
        return try await scopedClient.update(inNamespace: selector, resource)
    }

    // MARK: - YAML Operations

    /// Converts a Kubernetes resource to a YAML string representation.
    func getYAML<R: KubernetesAPIResource & Encodable>(_ resource: R) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(resource)

        // Convert JSON to a dictionary, then encode as YAML
        guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw KubernetesServiceError.yamlSerializationFailed("Could not convert resource to dictionary")
        }

        // Sanitize Foundation types (NSNumber, NSString) to Swift native types
        // that Yams can represent via NodeRepresentable
        let sanitized = sanitizeForYams(jsonObject)
        let yamlString = try Yams.dump(object: sanitized, allowUnicode: true, sortKeys: true)
        return yamlString
    }

    /// Recursively converts Foundation types (NSNumber, NSString, etc.) produced by
    /// JSONSerialization into Swift native types that conform to Yams' NodeRepresentable.
    private func sanitizeForYams(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitizeForYams($0) }
        case let array as [Any]:
            return array.map { sanitizeForYams($0) }
        case let number as NSNumber:
            // Detect NSNumber wrapping a Bool (CFBoolean) — must check before Int/Double
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            // Prefer Int when the value is integral
            let doubleVal = number.doubleValue
            let intVal = number.intValue
            if doubleVal == Double(intVal) && !number.stringValue.contains(".") {
                return intVal
            }
            return doubleVal
        case let string as NSString:
            return string as String
        case is NSNull:
            return NSNull()
        default:
            return "\(value)"
        }
    }

    /// Parses a YAML string and applies it as a Kubernetes resource.
    /// This method parses the YAML to determine the kind and then creates or updates accordingly.
    func applyYAML(_ yamlString: String, in namespace: String? = nil) async throws {
        // Parse YAML to determine kind and apiVersion
        guard let node = try Yams.compose(yaml: yamlString),
              let mapping = node.mapping else {
            throw KubernetesServiceError.yamlDeserializationFailed("Invalid YAML structure")
        }

        guard let kind = mapping[Yams.Node("kind")]?.string else {
            throw KubernetesServiceError.yamlDeserializationFailed("Missing 'kind' field in YAML")
        }

        // Convert YAML back to JSON for decoding with SwiftkubeModel types
        let jsonData = try yamlToJSON(yamlString)

        let decoder = JSONDecoder()

        let namespaceSelector: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces

        switch kind {
        case "Pod":
            let resource = try decoder.decode(core.v1.Pod.self, from: jsonData)
            _ = try await client.pods.create(inNamespace: namespaceSelector, resource)
        case "Deployment":
            let resource = try decoder.decode(apps.v1.Deployment.self, from: jsonData)
            _ = try await client.appsV1.deployments.create(inNamespace: namespaceSelector, resource)
        case "Service":
            let resource = try decoder.decode(core.v1.Service.self, from: jsonData)
            _ = try await client.services.create(inNamespace: namespaceSelector, resource)
        case "ConfigMap":
            let resource = try decoder.decode(core.v1.ConfigMap.self, from: jsonData)
            _ = try await client.configMaps.create(inNamespace: namespaceSelector, resource)
        case "Secret":
            let resource = try decoder.decode(core.v1.Secret.self, from: jsonData)
            _ = try await client.secrets.create(inNamespace: namespaceSelector, resource)
        case "Namespace":
            let resource = try decoder.decode(core.v1.Namespace.self, from: jsonData)
            _ = try await client.namespaces.create(resource)
        case "StatefulSet":
            let resource = try decoder.decode(apps.v1.StatefulSet.self, from: jsonData)
            _ = try await client.appsV1.statefulSets.create(inNamespace: namespaceSelector, resource)
        case "DaemonSet":
            let resource = try decoder.decode(apps.v1.DaemonSet.self, from: jsonData)
            _ = try await client.appsV1.daemonSets.create(inNamespace: namespaceSelector, resource)
        case "Job":
            let resource = try decoder.decode(batch.v1.Job.self, from: jsonData)
            _ = try await client.batchV1.jobs.create(inNamespace: namespaceSelector, resource)
        case "CronJob":
            let resource = try decoder.decode(batch.v1.CronJob.self, from: jsonData)
            _ = try await client.batchV1.cronJobs.create(inNamespace: namespaceSelector, resource)
        case "Ingress":
            let resource = try decoder.decode(networking.v1.Ingress.self, from: jsonData)
            _ = try await client.networkingV1.ingresses.create(inNamespace: namespaceSelector, resource)
        case "NetworkPolicy":
            let resource = try decoder.decode(networking.v1.NetworkPolicy.self, from: jsonData)
            _ = try await client.networkingV1.networkPolicies.create(inNamespace: namespaceSelector, resource)
        case "ServiceAccount":
            let resource = try decoder.decode(core.v1.ServiceAccount.self, from: jsonData)
            _ = try await client.serviceAccounts.create(inNamespace: namespaceSelector, resource)
        case "Role":
            let resource = try decoder.decode(rbac.v1.Role.self, from: jsonData)
            _ = try await client.rbacV1.roles.create(inNamespace: namespaceSelector, resource)
        case "ClusterRole":
            let resource = try decoder.decode(rbac.v1.ClusterRole.self, from: jsonData)
            _ = try await client.rbacV1.clusterRoles.create(resource)
        case "RoleBinding":
            let resource = try decoder.decode(rbac.v1.RoleBinding.self, from: jsonData)
            _ = try await client.rbacV1.roleBindings.create(inNamespace: namespaceSelector, resource)
        case "ClusterRoleBinding":
            let resource = try decoder.decode(rbac.v1.ClusterRoleBinding.self, from: jsonData)
            _ = try await client.rbacV1.clusterRoleBindings.create(resource)
        case "PersistentVolumeClaim":
            let resource = try decoder.decode(core.v1.PersistentVolumeClaim.self, from: jsonData)
            _ = try await client.persistentVolumeClaims.create(inNamespace: namespaceSelector, resource)
        case "PersistentVolume":
            let resource = try decoder.decode(core.v1.PersistentVolume.self, from: jsonData)
            _ = try await client.persistentVolumes.create(resource)
        default:
            throw KubernetesServiceError.unsupportedResourceKind(kind)
        }
    }

    // MARK: - Private Helpers

    /// Converts a YAML string to JSON Data.
    private func yamlToJSON(_ yamlString: String) throws -> Data {
        guard let yamlNode = try Yams.compose(yaml: yamlString) else {
            throw KubernetesServiceError.yamlDeserializationFailed("Failed to compose YAML node")
        }

        let jsonObject = yamlNodeToJSONObject(yamlNode)
        return try JSONSerialization.data(withJSONObject: jsonObject)
    }

    /// Recursively converts a Yams Node to a JSON-compatible object.
    private func yamlNodeToJSONObject(_ node: Yams.Node) -> Any {
        switch node {
        case .scalar(let scalar):
            if let boolValue = Bool(scalar.string) {
                return boolValue
            }
            if let intValue = Int(scalar.string) {
                return intValue
            }
            if let doubleValue = Double(scalar.string) {
                return doubleValue
            }
            if scalar.string == "null" || scalar.string == "~" {
                return NSNull()
            }
            return scalar.string
        case .mapping(let mapping):
            var dict: [String: Any] = [:]
            for (key, value) in mapping {
                if let keyString = key.string {
                    dict[keyString] = yamlNodeToJSONObject(value)
                }
            }
            return dict
        case .sequence(let sequence):
            return sequence.map { yamlNodeToJSONObject($0) }
        case .alias(let alias):
            // YAML aliases are references to anchored nodes; return the anchor name as a string.
            // In practice, Yams resolves aliases during compose so this case is rarely reached.
            return alias.anchor.rawValue
        }
    }

    // MARK: - Pod-Specific Operations

    /// Fetches logs for a pod (non-streaming).
    func logs(
        podName: String,
        in namespace: String,
        container: String? = nil,
        previous: Bool = false,
        timestamps: Bool = false,
        tailLines: Int? = nil
    ) async throws -> String {
        try await client.pods.logs(
            in: .namespace(namespace),
            name: podName,
            container: container,
            previous: previous,
            timestamps: timestamps,
            tailLines: tailLines
        )
    }

    /// Follows (streams) logs for a pod, returning a SwiftkubeClientTask.
    func followLogs(
        podName: String,
        in namespace: String,
        container: String? = nil,
        timestamps: Bool = false,
        tailLines: Int? = nil,
        retryStrategy: RetryStrategy = RetryStrategy.never
    ) async throws -> SwiftkubeClientTask<String> {
        try await client.pods.follow(
            in: .namespace(namespace),
            name: podName,
            container: container,
            timestamps: timestamps,
            tailLines: tailLines,
            retryStrategy: retryStrategy
        )
    }
}
