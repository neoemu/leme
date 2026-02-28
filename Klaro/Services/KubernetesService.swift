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

enum KubernetesOperationErrorCategory: String, Sendable {
    case validation
    case rbac
    case connectivity
    case unknown
}

struct KubernetesOperationError: LocalizedError, Sendable {
    let category: KubernetesOperationErrorCategory
    let detail: String

    var errorDescription: String? {
        switch category {
        case .validation:
            return "Validation error: \(detail)"
        case .rbac:
            return "Permission denied (RBAC): \(detail)"
        case .connectivity:
            return "Cluster connectivity error: \(detail)"
        case .unknown:
            return detail
        }
    }
}

struct ApplyResult: Sendable {
    enum Mode: String, Sendable {
        case patch
        case apply
    }

    let mode: Mode
    let stdout: String
    let warnings: [String]
}

struct CustomResourceDefinitionInfo: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let kind: String
    let plural: String
    let group: String
    let version: String
    let scope: String
    let shortNames: [String]

    var resourceIdentifier: String {
        "\(plural).\(group)"
    }

    var isNamespaced: Bool {
        scope.caseInsensitiveCompare("Namespaced") == .orderedSame
    }
}

struct CustomResourceItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let namespace: String?
    let status: String
    let age: Date?
    let labels: [String: String]
    let annotations: [String: String]
}

struct NodeUsageMetricsSample: Sendable {
    let cpuUsageCores: Double
    let memoryUsageGiB: Double
    let timestamp: Date?
}

struct NodeSummaryMetricsSample: Sendable {
    let timestamp: Date?
    let memoryWorkingSetGiB: Double?
    let networkRxTotalBytes: Double?
    let networkTxTotalBytes: Double?
    let diskUsageGiB: Double?
    let diskCapacityGiB: Double?
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

    // MARK: - Custom Resource Operations

    func listCustomResourceDefinitions(context: String? = nil) async throws -> [CustomResourceDefinitionInfo] {
        var arguments = ["get", "crd", "--request-timeout=15s", "-o", "json"]
        if let context, !context.isEmpty {
            arguments.append(contentsOf: ["--context", context])
        }

        let output = try executeKubectl(arguments: arguments)
        guard let jsonData = output.stdout.data(using: .utf8) else {
            throw KubernetesServiceError.operationFailed("Failed to decode CRD list output.")
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw KubernetesServiceError.operationFailed("Unexpected CRD list response shape.")
        }

        var definitions: [CustomResourceDefinitionInfo] = []
        for item in items {
            guard let metadata = item["metadata"] as? [String: Any],
                  let metadataName = metadata["name"] as? String,
                  let spec = item["spec"] as? [String: Any],
                  let names = spec["names"] as? [String: Any],
                  let plural = names["plural"] as? String,
                  let kind = names["kind"] as? String,
                  let group = spec["group"] as? String,
                  let scope = spec["scope"] as? String else {
                continue
            }

            let shortNames = names["shortNames"] as? [String] ?? []
            let versions = spec["versions"] as? [[String: Any]] ?? []
            let version = Self.preferredCRDVersion(from: versions)
                ?? (spec["version"] as? String)
                ?? "v1"

            definitions.append(
                CustomResourceDefinitionInfo(
                    id: metadataName,
                    name: metadataName,
                    kind: kind,
                    plural: plural,
                    group: group,
                    version: version,
                    scope: scope,
                    shortNames: shortNames
                )
            )
        }

        return definitions.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
            }
            return lhs.kind.localizedCaseInsensitiveCompare(rhs.kind) == .orderedAscending
        }
    }

    func listCustomResources(
        definition: CustomResourceDefinitionInfo,
        namespace: String?,
        context: String? = nil
    ) async throws -> [CustomResourceItem] {
        var arguments = ["get", definition.resourceIdentifier, "--request-timeout=15s"]

        if definition.isNamespaced {
            if let namespace, !namespace.isEmpty {
                arguments.append(contentsOf: ["-n", namespace])
            } else {
                arguments.append("-A")
            }
        }

        if let context, !context.isEmpty {
            arguments.append(contentsOf: ["--context", context])
        }

        arguments.append(contentsOf: ["-o", "json"])

        let output = try executeKubectl(arguments: arguments)
        guard let jsonData = output.stdout.data(using: .utf8) else {
            throw KubernetesServiceError.operationFailed("Failed to decode custom resource list output.")
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw KubernetesServiceError.operationFailed("Unexpected custom resource list response shape.")
        }

        return items.compactMap { item in
            guard let metadata = item["metadata"] as? [String: Any],
                  let name = metadata["name"] as? String else {
                return nil
            }

            let resourceNamespace = metadata["namespace"] as? String
            let id = resourceNamespace.map { "\($0)/\(name)" } ?? name
            let labels = metadata["labels"] as? [String: String] ?? [:]
            let annotations = metadata["annotations"] as? [String: String] ?? [:]
            let creationTimestamp = metadata["creationTimestamp"] as? String
            let status = Self.extractCustomResourceStatus(from: item)

            return CustomResourceItem(
                id: id,
                name: name,
                namespace: resourceNamespace,
                status: status,
                age: Self.parseKubernetesDate(creationTimestamp),
                labels: labels,
                annotations: annotations
            )
        }
        .sorted { lhs, rhs in
            if lhs.namespace == rhs.namespace {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return (lhs.namespace ?? "").localizedCaseInsensitiveCompare(rhs.namespace ?? "") == .orderedAscending
        }
    }

    func getCustomResourceYAML(
        definition: CustomResourceDefinitionInfo,
        name: String,
        namespace: String?,
        context: String? = nil
    ) async throws -> String {
        var arguments = ["get", definition.resourceIdentifier, name, "--request-timeout=15s"]
        if definition.isNamespaced, let namespace, !namespace.isEmpty {
            arguments.append(contentsOf: ["-n", namespace])
        }
        if let context, !context.isEmpty {
            arguments.append(contentsOf: ["--context", context])
        }
        arguments.append(contentsOf: ["-o", "yaml"])

        let output = try executeKubectl(arguments: arguments)
        return output.stdout
    }

    func deleteCustomResource(
        definition: CustomResourceDefinitionInfo,
        name: String,
        namespace: String?,
        context: String? = nil
    ) async throws {
        var arguments = ["delete", definition.resourceIdentifier, name, "--request-timeout=15s"]
        if definition.isNamespaced, let namespace, !namespace.isEmpty {
            arguments.append(contentsOf: ["-n", namespace])
        }
        if let context, !context.isEmpty {
            arguments.append(contentsOf: ["--context", context])
        }

        _ = try executeKubectl(arguments: arguments)
    }

    func hasAnyCustomResourceInstances(
        definition: CustomResourceDefinitionInfo,
        namespace: String?,
        context: String? = nil
    ) async throws -> Bool {
        let rawPath: String
        if definition.isNamespaced, let namespace, !namespace.isEmpty {
            rawPath = "/apis/\(definition.group)/\(definition.version)/namespaces/\(namespace)/\(definition.plural)?limit=1"
        } else {
            rawPath = "/apis/\(definition.group)/\(definition.version)/\(definition.plural)?limit=1"
        }

        var arguments = ["get", "--raw", rawPath, "--request-timeout=2s"]
        if let context, !context.isEmpty {
            arguments.append(contentsOf: ["--context", context])
        }

        let output = try executeKubectl(arguments: arguments)
        guard let jsonData = output.stdout.data(using: .utf8) else {
            return false
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            return false
        }

        return !items.isEmpty
    }

    func fetchNodeUsageMetrics(name: String) async throws -> NodeUsageMetricsSample {
        let rawPath = "/apis/metrics.k8s.io/v1beta1/nodes/\(name)"
        let output = try executeKubectl(arguments: ["get", "--raw", rawPath, "--request-timeout=3s"])

        guard let jsonData = output.stdout.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            throw KubernetesServiceError.operationFailed("Failed to decode node metrics output.")
        }

        let cpuUsageRaw = usage["cpu"] as? String ?? "0"
        let memoryUsageRaw = usage["memory"] as? String ?? "0"
        let timestampString = root["timestamp"] as? String

        let timestamp: Date?
        if let timestampString {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampString) ?? ISO8601DateFormatter().date(from: timestampString)
        } else {
            timestamp = nil
        }

        return NodeUsageMetricsSample(
            cpuUsageCores: cpuUsageRaw.parseKubernetesCPU(),
            memoryUsageGiB: memoryUsageRaw.parseKubernetesMemoryGiB(),
            timestamp: timestamp
        )
    }

    func fetchNodeSummaryMetrics(name: String) async throws -> NodeSummaryMetricsSample {
        let rawPath = "/api/v1/nodes/\(name)/proxy/stats/summary"
        let output = try executeKubectl(arguments: ["get", "--raw", rawPath, "--request-timeout=3s"])

        guard let jsonData = output.stdout.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let node = root["node"] as? [String: Any] else {
            throw KubernetesServiceError.operationFailed("Failed to decode node summary output.")
        }

        let memory = node["memory"] as? [String: Any]
        let network = node["network"] as? [String: Any]
        let filesystem = node["fs"] as? [String: Any]

        let timestamp = Self.parseSummaryDate(
            memory?["time"] as? String
                ?? network?["time"] as? String
                ?? filesystem?["time"] as? String
        )

        let memoryWorkingSetGiB = Self.parseSummaryDouble(memory?["workingSetBytes"]).map { $0 / (1024 * 1024 * 1024) }
        let networkRxTotalBytes = Self.parseSummaryDouble(network?["rxBytes"])
        let networkTxTotalBytes = Self.parseSummaryDouble(network?["txBytes"])
        let diskUsedGiB = Self.parseSummaryDouble(filesystem?["usedBytes"]).map { $0 / (1024 * 1024 * 1024) }
        let diskCapacityGiB = Self.parseSummaryDouble(filesystem?["capacityBytes"]).map { $0 / (1024 * 1024 * 1024) }

        return NodeSummaryMetricsSample(
            timestamp: timestamp,
            memoryWorkingSetGiB: memoryWorkingSetGiB,
            networkRxTotalBytes: networkRxTotalBytes,
            networkTxTotalBytes: networkTxTotalBytes,
            diskUsageGiB: diskUsedGiB,
            diskCapacityGiB: diskCapacityGiB
        )
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
    ) async throws -> ApplyResult {
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
            let output = try executeKubectl(arguments: patchArguments, stdin: patchRequest.targetManifestYAML)
            return ApplyResult(
                mode: .patch,
                stdout: output.stdout,
                warnings: parseKubectlWarnings(from: output.stderr)
            )
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
        let output = try executeKubectl(arguments: applyArguments, stdin: sanitizedManifest)
        return ApplyResult(
            mode: .apply,
            stdout: output.stdout,
            warnings: parseKubectlWarnings(from: output.stderr)
        )
    }

    private struct KubectlCommandOutput {
        let stdout: String
        let stderr: String
    }

    private func executeKubectl(arguments: [String], stdin: String? = nil) throws -> KubectlCommandOutput {
        let kubectlPath = try findKubectl()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent("klaro-kubectl-stdout-\(UUID().uuidString).tmp")
        let stderrURL = tempDirectory.appendingPathComponent("klaro-kubectl-stderr-\(UUID().uuidString).tmp")

        guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: stderrURL.path, contents: nil),
              let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
              let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path) else {
            throw KubernetesServiceError.operationFailed("Failed to create kubectl output buffers.")
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdinPipe.fileHandleForWriting.close()
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

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
            throw KubernetesOperationError(
                category: .connectivity,
                detail: "Failed to start kubectl: \(error.localizedDescription)"
            )
        }

        if let stdin, let inputData = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            let message = detail.isEmpty
                ? "kubectl command failed with exit code \(process.terminationStatus)"
                : detail

            throw KubernetesOperationError(
                category: Self.classifyOperationError(detail: message),
                detail: message
            )
        }

        return KubectlCommandOutput(stdout: stdout, stderr: stderr)
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

    static func classifyOperationError(detail: String) -> KubernetesOperationErrorCategory {
        let normalized = detail.lowercased()

        if normalized.contains("forbidden")
            || normalized.contains("cannot list resource")
            || normalized.contains("cannot get resource")
            || normalized.contains("cannot patch resource")
            || normalized.contains("cannot create resource")
            || normalized.contains("cannot update resource")
            || normalized.contains("cannot delete resource") {
            return .rbac
        }

        if normalized.contains("unable to connect to the server")
            || normalized.contains("connection refused")
            || normalized.contains("timed out")
            || normalized.contains("timeout")
            || normalized.contains("context deadline exceeded")
            || normalized.contains("no such host")
            || normalized.contains("i/o timeout")
            || normalized.contains("tls handshake timeout")
            || normalized.contains("connection reset by peer") {
            return .connectivity
        }

        if normalized.contains("error validating")
            || normalized.contains("validation failed")
            || normalized.contains("invalid")
            || normalized.contains("cannot be handled as")
            || normalized.contains("cannot parse")
            || normalized.contains("json parse")
            || normalized.contains("yaml parse") {
            return .validation
        }

        return .unknown
    }

    static func classifyOperationError(_ error: Error) -> KubernetesOperationErrorCategory {
        if let operationError = error as? KubernetesOperationError {
            return operationError.category
        }
        if let serviceError = error as? KubernetesServiceError,
           case .operationFailed(let detail) = serviceError {
            return classifyOperationError(detail: detail)
        }
        return .unknown
    }

    private func parseKubectlWarnings(from stderr: String) -> [String] {
        guard !stderr.isEmpty else { return [] }
        return stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.lowercased().hasPrefix("warning:") }
    }

    private static func preferredCRDVersion(from versions: [[String: Any]]) -> String? {
        if let storageVersion = versions.first(where: { ($0["storage"] as? Bool) == true }),
           let name = storageVersion["name"] as? String {
            return name
        }

        if let servedVersion = versions.first(where: { ($0["served"] as? Bool) == true }),
           let name = servedVersion["name"] as? String {
            return name
        }

        return versions.first?["name"] as? String
    }

    private static func extractCustomResourceStatus(from item: [String: Any]) -> String {
        guard let status = item["status"] as? [String: Any] else {
            return "Active"
        }

        if let phase = status["phase"] as? String, !phase.isEmpty {
            return phase
        }

        if let conditions = status["conditions"] as? [[String: Any]] {
            if let healthy = conditions.first(where: { ($0["status"] as? String) == "True" }),
               let type = healthy["type"] as? String, !type.isEmpty {
                return type
            }

            if let latest = conditions.last,
               let type = latest["type"] as? String, !type.isEmpty {
                return type
            }
        }

        if let reason = status["reason"] as? String, !reason.isEmpty {
            return reason
        }

        return "Active"
    }

    private static func parseKubernetesDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func parseSummaryDate(_ value: String?) -> Date? {
        parseKubernetesDate(value)
    }

    private static func parseSummaryDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
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
