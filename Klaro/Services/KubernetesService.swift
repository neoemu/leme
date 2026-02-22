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

    private struct ManifestIdentity: Equatable {
        let apiVersion: String
        let kind: String
        let name: String
        let namespace: String?
    }

    private struct PatchRequest {
        let patchJSON: String
        let targetManifestYAML: String
        let namespace: String?
    }

    private static let lastAppliedConfigurationAnnotationKey = "kubectl.kubernetes.io/last-applied-configuration"
    private static let metadataFieldsToStripOnApply: Set<String> = [
        "creationTimestamp",
        "resourceVersion",
        "uid",
        "selfLink",
        "generation",
        "managedFields",
        "deletionTimestamp",
        "deletionGracePeriodSeconds",
    ]

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
        encoder.dateEncodingStrategy = .iso8601
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

    /// Applies a YAML manifest by preferring a merge-patch of only changed fields.
    /// Falls back to `kubectl apply -f -` when patch mode cannot be used safely.
    func applyYAML(
        _ yamlString: String,
        originalYAML: String? = nil,
        in namespace: String? = nil,
        context: String? = nil
    ) async throws {
        if let originalYAML,
           let patchRequest = try buildPatchRequest(
               originalYAML: originalYAML,
               editedYAML: yamlString,
               fallbackNamespace: namespace
           ) {
            var patchArguments = ["patch", "--type", "merge", "--patch", patchRequest.patchJSON, "-f", "-"]
            if let context, !context.isEmpty {
                patchArguments.append(contentsOf: ["--context", context])
            }
            if let requestNamespace = patchRequest.namespace, !requestNamespace.isEmpty {
                patchArguments.append(contentsOf: ["-n", requestNamespace])
            }
            _ = try executeKubectl(arguments: patchArguments, stdin: patchRequest.targetManifestYAML)
            return
        }

        let sanitizedManifest = try sanitizeManifestForApply(yamlString)
        var applyArguments = ["apply"]
        if let context, !context.isEmpty {
            applyArguments.append(contentsOf: ["--context", context])
        }
        if let namespace, !namespace.isEmpty {
            applyArguments.append(contentsOf: ["-n", namespace])
        }
        applyArguments.append(contentsOf: ["-f", "-"])
        _ = try executeKubectl(arguments: applyArguments, stdin: sanitizedManifest)
    }

    @discardableResult
    private func executeKubectl(arguments: [String], stdin: String) throws -> String {
        let kubectlPath = try findKubectl()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        } else {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw KubernetesServiceError.operationFailed("Failed to start kubectl: \(error.localizedDescription)")
        }

        if let inputData = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            throw KubernetesServiceError.operationFailed(
                detail.isEmpty
                    ? "kubectl command failed with exit code \(process.terminationStatus)"
                    : detail
            )
        }

        return stdout
    }

    private func findKubectl() throws -> String {
        let commonPaths = [
            "/usr/local/bin/kubectl",
            "/opt/homebrew/bin/kubectl",
            "/usr/bin/kubectl",
            "/opt/local/bin/kubectl",
        ]

        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["kubectl"]
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // fall through to error
        }

        throw KubernetesServiceError.operationFailed(
            "kubectl not found. Install kubectl and ensure it is in PATH."
        )
    }

    // MARK: - Private Helpers

    /// Removes server-managed fields that commonly make `kubectl apply -f -` fail
    /// when the manifest originates from a GET response.
    private func sanitizeManifestForApply(_ yamlString: String) throws -> String {
        let nodes = Array(try Yams.compose_all(yaml: yamlString))
        guard !nodes.isEmpty else {
            return yamlString
        }

        let sanitizedDocuments: [String] = try nodes.map { node in
            let jsonObject = yamlNodeToJSONObject(node)
            let cleaned = pruneKubernetesNoiseForApply(in: jsonObject)
            let sanitized = sanitizeForYams(cleaned)
            return try Yams.dump(object: sanitized, allowUnicode: true, sortKeys: true)
        }

        return sanitizedDocuments.joined(separator: "\n---\n")
    }

    /// Recursively strips noisy/immutable fields from Kubernetes objects.
    private func pruneKubernetesNoiseForApply(in value: Any) -> Any {
        switch value {
        case var dict as [String: Any]:
            for (key, nestedValue) in dict {
                dict[key] = pruneKubernetesNoiseForApply(in: nestedValue)
            }

            dict.removeValue(forKey: "status")

            if var metadata = dict["metadata"] as? [String: Any] {
                for key in Self.metadataFieldsToStripOnApply {
                    metadata.removeValue(forKey: key)
                }

                if var annotations = metadata["annotations"] as? [String: Any] {
                    annotations.removeValue(forKey: Self.lastAppliedConfigurationAnnotationKey)
                    if annotations.isEmpty {
                        metadata.removeValue(forKey: "annotations")
                    } else {
                        metadata["annotations"] = annotations
                    }
                }

                dict["metadata"] = metadata
            }

            return dict
        case let array as [Any]:
            return array.map { pruneKubernetesNoiseForApply(in: $0) }
        default:
            return value
        }
    }

    /// Builds a merge-patch request from original and edited YAML manifests.
    /// Returns nil when patch mode cannot be safely used (for example multi-doc edits).
    private func buildPatchRequest(
        originalYAML: String,
        editedYAML: String,
        fallbackNamespace: String?
    ) throws -> PatchRequest? {
        let originalDocuments = try parseYAMLDocuments(originalYAML)
        let editedDocuments = try parseYAMLDocuments(editedYAML)

        guard originalDocuments.count == 1, editedDocuments.count == 1 else {
            return nil
        }

        let cleanedOriginalAny = pruneKubernetesNoiseForApply(in: originalDocuments[0])
        let cleanedEditedAny = pruneKubernetesNoiseForApply(in: editedDocuments[0])

        guard let cleanedOriginal = cleanedOriginalAny as? [String: Any],
              let cleanedEdited = cleanedEditedAny as? [String: Any] else {
            return nil
        }

        guard let originalIdentity = manifestIdentity(from: cleanedOriginal),
              let editedIdentity = manifestIdentity(from: cleanedEdited),
              originalIdentity == editedIdentity else {
            return nil
        }

        guard var patchObject = mergePatchDiff(from: cleanedOriginal, to: cleanedEdited) as? [String: Any] else {
            throw KubernetesServiceError.operationFailed("No changes to apply.")
        }

        patchObject.removeValue(forKey: "apiVersion")
        patchObject.removeValue(forKey: "kind")

        if var metadataPatch = patchObject["metadata"] as? [String: Any] {
            metadataPatch.removeValue(forKey: "name")
            metadataPatch.removeValue(forKey: "namespace")
            if metadataPatch.isEmpty {
                patchObject.removeValue(forKey: "metadata")
            } else {
                patchObject["metadata"] = metadataPatch
            }
        }

        guard !patchObject.isEmpty else {
            throw KubernetesServiceError.operationFailed("No changes to apply.")
        }

        let patchData = try JSONSerialization.data(withJSONObject: patchObject)
        guard let patchJSON = String(data: patchData, encoding: .utf8) else {
            throw KubernetesServiceError.operationFailed("Failed to encode patch payload.")
        }

        let requestNamespace: String?
        if let manifestNamespace = editedIdentity.namespace, !manifestNamespace.isEmpty {
            requestNamespace = manifestNamespace
        } else if originalIdentity.namespace != nil {
            requestNamespace = fallbackNamespace
        } else {
            requestNamespace = nil
        }
        var targetMetadata: [String: Any] = ["name": editedIdentity.name]
        if let requestNamespace, !requestNamespace.isEmpty {
            targetMetadata["namespace"] = requestNamespace
        }
        let targetManifest: [String: Any] = [
            "apiVersion": editedIdentity.apiVersion,
            "kind": editedIdentity.kind,
            "metadata": targetMetadata,
        ]
        let targetManifestYAML = try Yams.dump(object: sanitizeForYams(targetManifest), allowUnicode: true, sortKeys: true)

        return PatchRequest(
            patchJSON: patchJSON,
            targetManifestYAML: targetManifestYAML,
            namespace: requestNamespace
        )
    }

    private func parseYAMLDocuments(_ yamlString: String) throws -> [[String: Any]] {
        let nodes = Array(try Yams.compose_all(yaml: yamlString))
        guard !nodes.isEmpty else { return [] }

        var documents: [[String: Any]] = []
        for node in nodes {
            let object = yamlNodeToJSONObject(node)
            if let mapping = object as? [String: Any] {
                documents.append(mapping)
            }
        }
        return documents
    }

    private func manifestIdentity(from document: [String: Any]) -> ManifestIdentity? {
        guard let apiVersion = document["apiVersion"] as? String,
              let kind = document["kind"] as? String,
              let metadata = document["metadata"] as? [String: Any],
              let name = metadata["name"] as? String else {
            return nil
        }

        return ManifestIdentity(
            apiVersion: apiVersion,
            kind: kind,
            name: name,
            namespace: metadata["namespace"] as? String
        )
    }

    private func mergePatchDiff(from original: Any, to updated: Any) -> Any? {
        switch (original, updated) {
        case let (originalDict as [String: Any], updatedDict as [String: Any]):
            var patch: [String: Any] = [:]
            let keys = Set(originalDict.keys).union(updatedDict.keys)

            for key in keys {
                let oldValue = originalDict[key]
                let newValue = updatedDict[key]

                switch (oldValue, newValue) {
                case (_?, nil):
                    patch[key] = NSNull()
                case (nil, let newValue?):
                    patch[key] = newValue
                case (let oldValue?, let newValue?):
                    if let nestedDiff = mergePatchDiff(from: oldValue, to: newValue) {
                        patch[key] = nestedDiff
                    }
                case (nil, nil):
                    break
                }
            }

            return patch.isEmpty ? nil : patch

        case let (originalArray as [Any], updatedArray as [Any]):
            return valuesDeepEqual(originalArray, updatedArray) ? nil : updatedArray

        default:
            return valuesDeepEqual(original, updated) ? nil : updated
        }
    }

    private func valuesDeepEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case (is NSNull, is NSNull):
            return true
        case let (left as [String: Any], right as [String: Any]):
            guard left.count == right.count else { return false }
            for (key, leftValue) in left {
                guard let rightValue = right[key], valuesDeepEqual(leftValue, rightValue) else {
                    return false
                }
            }
            return true
        case let (left as [Any], right as [Any]):
            guard left.count == right.count else { return false }
            for (leftValue, rightValue) in zip(left, right) {
                if !valuesDeepEqual(leftValue, rightValue) {
                    return false
                }
            }
            return true
        case let (left as NSNumber, right as NSNumber):
            if CFGetTypeID(left) == CFBooleanGetTypeID() || CFGetTypeID(right) == CFBooleanGetTypeID() {
                return left.boolValue == right.boolValue
            }
            return left == right
        case let (left as String, right as String):
            return left == right
        case let (left as Bool, right as Bool):
            return left == right
        case let (left as Int, right as Int):
            return left == right
        case let (left as Double, right as Double):
            return left == right
        case let (left as Int, right as Double):
            return Double(left) == right
        case let (left as Double, right as Int):
            return left == Double(right)
        default:
            return false
        }
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

    // MARK: - Scale Operations

    func scaleDeployment(name: String, in namespace: String?, replicas: Int32) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var scale = try await client.appsV1.deployments.getScale(in: ns, name: name)
        scale.spec?.replicas = replicas
        _ = try await client.appsV1.deployments.updateScale(in: ns, name: name, scale: scale)
    }

    func scaleStatefulSet(name: String, in namespace: String?, replicas: Int32) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var scale = try await client.appsV1.statefulSets.getScale(in: ns, name: name)
        scale.spec?.replicas = replicas
        _ = try await client.appsV1.statefulSets.updateScale(in: ns, name: name, scale: scale)
    }

    func scaleReplicaSet(name: String, in namespace: String?, replicas: Int32) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var scale = try await client.appsV1.replicaSets.getScale(in: ns, name: name)
        scale.spec?.replicas = replicas
        _ = try await client.appsV1.replicaSets.updateScale(in: ns, name: name, scale: scale)
    }

    // MARK: - Restart Operations (Rollout Restart)

    func restartDeployment(name: String, in namespace: String?) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var resource = try await client.appsV1.deployments.get(in: ns, name: name)
        if resource.spec?.template.metadata?.annotations == nil {
            resource.spec?.template.metadata?.annotations = [:]
        }
        resource.spec?.template.metadata?.annotations?["kubectl.kubernetes.io/restartedAt"] = ISO8601DateFormatter().string(from: Date())
        _ = try await client.appsV1.deployments.update(inNamespace: ns, resource)
    }

    func restartStatefulSet(name: String, in namespace: String?) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var resource = try await client.appsV1.statefulSets.get(in: ns, name: name)
        if resource.spec?.template.metadata?.annotations == nil {
            resource.spec?.template.metadata?.annotations = [:]
        }
        resource.spec?.template.metadata?.annotations?["kubectl.kubernetes.io/restartedAt"] = ISO8601DateFormatter().string(from: Date())
        _ = try await client.appsV1.statefulSets.update(inNamespace: ns, resource)
    }

    func restartDaemonSet(name: String, in namespace: String?) async throws {
        let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces
        var resource = try await client.appsV1.daemonSets.get(in: ns, name: name)
        if resource.spec?.template.metadata?.annotations == nil {
            resource.spec?.template.metadata?.annotations = [:]
        }
        resource.spec?.template.metadata?.annotations?["kubectl.kubernetes.io/restartedAt"] = ISO8601DateFormatter().string(from: Date())
        _ = try await client.appsV1.daemonSets.update(inNamespace: ns, resource)
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
