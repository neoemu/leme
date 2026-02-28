import Foundation
import SwiftkubeClient
import SwiftkubeModel
import Yams

struct NodeMetricSummary: Sendable {
    let cpuRequestedCores: Double
    let cpuAllocatableCores: Double
    let cpuCapacityCores: Double
    let memoryRequestedGiB: Double
    let memoryAllocatableGiB: Double
    let memoryCapacityGiB: Double
    let podCount: Int
    let podAllocatable: Int
    let podCapacity: Int
}

struct NodePropertyItem: Identifiable, Sendable {
    let id: String
    let key: String
    let value: String
}

struct NodeResourceItem: Identifiable, Sendable {
    let id: String
    let name: String
    let value: String
}

struct NodePodItem: Identifiable, Sendable {
    let id: String
    let name: String
    let namespace: String
    let ready: String
    let cpu: String
    let memory: String
    let status: String
}

struct NodeOverview: Sendable {
    let metrics: NodeMetricSummary
    let properties: [NodePropertyItem]
    let capacity: [NodeResourceItem]
    let allocatable: [NodeResourceItem]
    let pods: [NodePodItem]
}

@Observable
@MainActor
final class ResourceDetailViewModel {
    private static let lastAppliedConfigurationAnnotationKey = "kubectl.kubernetes.io/last-applied-configuration"

    var resourceYAML: String = "" {
        didSet {
            cleanResourceYAML = Self.makeCleanYAML(from: resourceYAML)
        }
    }
    private(set) var cleanResourceYAML: String = ""
    var isLoading = false
    var errorMessage: String?
    var metadata: [String: String] = [:]
    var labels: [String: String] = [:]
    var annotations: [String: String] = [:]
    var events: [ResourceItem] = []
    var nodeOverview: NodeOverview?

    private let kubernetesService: KubernetesService

    init(client: KubernetesClient) {
        self.kubernetesService = KubernetesService(client: client)
    }

    var filteredAnnotations: [String: String] {
        annotations.filter { $0.key != Self.lastAppliedConfigurationAnnotationKey }
    }

    // MARK: - Load Pod Detail

    func loadPodDetail(name: String, namespace: String) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        do {
            let pod = try await kubernetesService.get(core.v1.Pod.self, name: name, in: namespace)
            extractMetadata(from: pod)
            // YAML is best-effort — don't block overview on serialization failure
            do {
                resourceYAML = try await kubernetesService.getYAML(pod)
            } catch {
                resourceYAML = "# Error loading YAML: \(error.localizedDescription)"
            }
            await loadEvents(forResource: name, namespace: namespace)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Load Deployment Detail

    func loadDeploymentDetail(name: String, namespace: String) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        do {
            let deployment = try await kubernetesService.get(apps.v1.Deployment.self, name: name, in: namespace)
            extractMetadata(from: deployment)
            do {
                resourceYAML = try await kubernetesService.getYAML(deployment)
            } catch {
                resourceYAML = "# Error loading YAML: \(error.localizedDescription)"
            }
            await loadEvents(forResource: name, namespace: namespace)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Load Generic Detail

    func loadDetail<R: KubernetesAPIResource & NamespacedResource & ReadableResource & Encodable>(
        _ type: R.Type,
        name: String,
        namespace: String
    ) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        do {
            let resource = try await kubernetesService.get(type, name: name, in: namespace)
            extractMetadata(from: resource)
            do {
                resourceYAML = try await kubernetesService.getYAML(resource)
            } catch {
                resourceYAML = "# Error loading YAML: \(error.localizedDescription)"
            }
            await loadEvents(forResource: name, namespace: namespace)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadClusterScopedDetail<R: KubernetesAPIResource & ClusterScopedResource & ReadableResource & Encodable>(
        _ type: R.Type,
        name: String
    ) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        do {
            let resource = try await kubernetesService.getClusterScoped(type, name: name)
            extractMetadata(from: resource)
            do {
                resourceYAML = try await kubernetesService.getYAML(resource)
            } catch {
                resourceYAML = "# Error loading YAML: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadCustomResourceDetail(
        definition: CustomResourceDefinitionInfo,
        name: String,
        namespace: String?,
        context: String?
    ) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        metadata = [:]
        labels = [:]
        annotations = [:]
        events = []

        do {
            resourceYAML = try await kubernetesService.getCustomResourceYAML(
                definition: definition,
                name: name,
                namespace: namespace,
                context: context
            )

            extractCustomResourceMetadata(from: resourceYAML, fallbackName: name, fallbackNamespace: namespace, definition: definition)

            if definition.isNamespaced, let namespace {
                await loadEvents(forResource: name, namespace: namespace)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadNodeDetail(name: String) async {
        isLoading = true
        errorMessage = nil
        nodeOverview = nil
        do {
            let node = try await kubernetesService.getClusterScoped(core.v1.Node.self, name: name)
            extractMetadata(from: node)

            do {
                resourceYAML = try await kubernetesService.getYAML(node)
            } catch {
                resourceYAML = "# Error loading YAML: \(error.localizedDescription)"
            }

            let allPods = try await kubernetesService.list(core.v1.Pod.self, in: nil).items
            nodeOverview = Self.extractNodeOverview(from: node, allPods: allPods)
            await loadClusterScopedEvents(forResource: name, kind: "Node")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Apply YAML

    func applyYAML(_ yaml: String, namespace: String?) async {
        do {
            _ = try await kubernetesService.applyYAML(yaml, in: namespace)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Events

    private func loadEvents(forResource name: String, namespace: String) async {
        do {
            let eventList = try await kubernetesService.list(core.v1.Event.self, in: namespace)
            events = eventList.items
                .filter { event in
                    event.involvedObject.name == name
                }
                .map { event in
                    ResourceItem(
                        id: "\(event.metadata?.namespace ?? "")/\(event.name ?? "")",
                        name: event.name ?? "",
                        namespace: event.metadata?.namespace,
                        status: event.type ?? "Normal",
                        age: event.metadata?.creationTimestamp,
                        labels: [:],
                        annotations: [:],
                        kind: .event,
                        extraColumns: [
                            "reason": event.reason ?? "",
                            "message": event.message ?? "",
                            "count": "\(event.count ?? 0)",
                            "object": "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")"
                        ]
                    )
                }
        } catch {
            // Events are best-effort
        }
    }

    private func loadClusterScopedEvents(forResource name: String, kind: String) async {
        do {
            let eventList = try await kubernetesService.list(core.v1.Event.self, in: nil)
            events = eventList.items
                .filter { event in
                    event.involvedObject.name == name &&
                    (event.involvedObject.kind ?? "") == kind
                }
                .map { event in
                    ResourceItem(
                        id: "\(event.metadata?.namespace ?? "")/\(event.name ?? "")",
                        name: event.name ?? "",
                        namespace: event.metadata?.namespace,
                        status: event.type ?? "Normal",
                        age: event.lastTimestamp ?? event.metadata?.creationTimestamp,
                        labels: [:],
                        annotations: [:],
                        kind: .event,
                        extraColumns: [
                            "reason": event.reason ?? "",
                            "message": event.message ?? "",
                            "count": "\(event.count ?? 0)",
                            "object": "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")"
                        ]
                    )
                }
        } catch {
            // Events are best-effort
        }
    }

    // MARK: - Helpers

    private func extractMetadata<R: KubernetesAPIResource>(from resource: R) {
        metadata = [:]
        labels = [:]
        annotations = [:]

        if let meta = resource.metadata {
            metadata["name"] = meta.name
            metadata["namespace"] = meta.namespace ?? ""
            metadata["uid"] = meta.uid ?? ""
            metadata["resourceVersion"] = meta.resourceVersion ?? ""
            if let ts = meta.creationTimestamp {
                metadata["creationTimestamp"] = ts.description
            }
            labels = meta.labels ?? [:]
            annotations = meta.annotations ?? [:]
        }
    }

    private func extractCustomResourceMetadata(
        from yaml: String,
        fallbackName: String,
        fallbackNamespace: String?,
        definition: CustomResourceDefinitionInfo
    ) {
        metadata = [:]
        labels = [:]
        annotations = [:]

        metadata["name"] = fallbackName
        metadata["namespace"] = fallbackNamespace ?? ""
        metadata["kind"] = definition.kind
        metadata["apiVersion"] = "\(definition.group)/\(definition.version)"

        guard let loaded = try? Yams.load(yaml: yaml),
              let object = loaded as? [String: Any] else {
            return
        }

        if let apiVersion = object["apiVersion"] as? String {
            metadata["apiVersion"] = apiVersion
        }
        if let kind = object["kind"] as? String {
            metadata["kind"] = kind
        }

        guard let metadataNode = object["metadata"] as? [String: Any] else {
            return
        }

        if let name = metadataNode["name"] as? String {
            metadata["name"] = name
        }
        if let namespace = metadataNode["namespace"] as? String {
            metadata["namespace"] = namespace
        }
        if let uid = metadataNode["uid"] as? String {
            metadata["uid"] = uid
        }
        if let resourceVersion = metadataNode["resourceVersion"] as? String {
            metadata["resourceVersion"] = resourceVersion
        }
        if let creationTimestamp = metadataNode["creationTimestamp"] as? String {
            metadata["creationTimestamp"] = creationTimestamp
        }
        labels = metadataNode["labels"] as? [String: String] ?? [:]
        annotations = metadataNode["annotations"] as? [String: String] ?? [:]
    }

    private static func extractNodeOverview(from node: core.v1.Node, allPods: [core.v1.Pod]) -> NodeOverview {
        let nodeName = node.name ?? ""
        let nodePods = allPods.filter { $0.spec?.nodeName == nodeName }

        let capacityMap: [String: String] = (node.status?.capacity ?? [:]).mapValues { $0.description }
        let allocatableMap: [String: String] = (node.status?.allocatable ?? [:]).mapValues { $0.description }

        let cpuCapacityCores = (capacityMap["cpu"] ?? "0").parseKubernetesCPU()
        let cpuAllocatableCores = (allocatableMap["cpu"] ?? "0").parseKubernetesCPU()
        let memoryCapacityGiB = (capacityMap["memory"] ?? "0").parseKubernetesMemoryGiB()
        let memoryAllocatableGiB = (allocatableMap["memory"] ?? "0").parseKubernetesMemoryGiB()
        let podCapacity = Int(capacityMap["pods"] ?? "0") ?? 0
        let podAllocatable = Int(allocatableMap["pods"] ?? "0") ?? 0

        var cpuRequestedCores = 0.0
        var memoryRequestedGiB = 0.0

        let podItems = nodePods
            .map { pod -> NodePodItem in
                let podName = pod.name ?? ""
                let namespace = pod.metadata?.namespace ?? "-"
                let readiness = PodStatusFormatter.readySummary(for: pod)
                let ready = "\(readiness.ready)/\(readiness.total)"

                var podCPU = 0.0
                var podMemory = 0.0
                for container in pod.spec?.containers ?? [] {
                    if let cpuReq = container.resources?.requests?["cpu"]?.description {
                        podCPU += cpuReq.parseKubernetesCPU()
                    }
                    if let memReq = container.resources?.requests?["memory"]?.description {
                        podMemory += memReq.parseKubernetesMemoryGiB()
                    }
                }
                cpuRequestedCores += podCPU
                memoryRequestedGiB += podMemory

                return NodePodItem(
                    id: "\(namespace)/\(podName)",
                    name: podName,
                    namespace: namespace,
                    ready: ready,
                    cpu: formatCPU(podCPU),
                    memory: formatMemoryGiB(podMemory),
                    status: PodStatusFormatter.displayStatus(for: pod)
                )
            }
            .sorted { lhs, rhs in
                if lhs.namespace == rhs.namespace {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.namespace.localizedCaseInsensitiveCompare(rhs.namespace) == .orderedAscending
            }

        let addresses = node.status?.addresses ?? []
        let internalIP = addresses.first(where: { $0.type == "InternalIP" })?.address ?? "-"
        let hostname = addresses.first(where: { $0.type == "Hostname" })?.address ?? "-"
        let nodeInfo = node.status?.nodeInfo
        let creationTimestamp = node.metadata?.creationTimestamp?.description ?? "-"
        let labels = node.metadata?.labels ?? [:]
        let annotations = node.metadata?.annotations ?? [:]
        let readyCondition = node.status?.conditions?.first(where: { $0.type == "Ready" })
        let conditionText: String = {
            guard let readyCondition else { return "Unknown" }
            return readyCondition.status == "True" ? "Ready" : "NotReady"
        }()

        let properties: [NodePropertyItem] = [
            NodePropertyItem(id: "created", key: "Created", value: creationTimestamp),
            NodePropertyItem(id: "name", key: "Name", value: nodeName),
            NodePropertyItem(id: "labels", key: "Labels", value: "\(labels.count)"),
            NodePropertyItem(id: "annotations", key: "Annotations", value: "\(annotations.count)"),
            NodePropertyItem(id: "addresses", key: "Addresses", value: "InternalIP: \(internalIP) • Hostname: \(hostname)"),
            NodePropertyItem(id: "os", key: "OS", value: nodeInfo?.operatingSystem ?? "-"),
            NodePropertyItem(id: "osImage", key: "OS Image", value: nodeInfo?.osImage ?? "-"),
            NodePropertyItem(id: "kernelVersion", key: "Kernel Version", value: nodeInfo?.kernelVersion ?? "-"),
            NodePropertyItem(id: "containerRuntimeVersion", key: "Container Runtime", value: nodeInfo?.containerRuntimeVersion ?? "-"),
            NodePropertyItem(id: "kubeletVersion", key: "Kubelet Version", value: nodeInfo?.kubeletVersion ?? "-"),
            NodePropertyItem(id: "conditions", key: "Conditions", value: conditionText),
        ]

        return NodeOverview(
            metrics: NodeMetricSummary(
                cpuRequestedCores: cpuRequestedCores,
                cpuAllocatableCores: cpuAllocatableCores,
                cpuCapacityCores: cpuCapacityCores,
                memoryRequestedGiB: memoryRequestedGiB,
                memoryAllocatableGiB: memoryAllocatableGiB,
                memoryCapacityGiB: memoryCapacityGiB,
                podCount: nodePods.count,
                podAllocatable: podAllocatable,
                podCapacity: podCapacity
            ),
            properties: properties,
            capacity: orderedNodeResources(from: capacityMap),
            allocatable: orderedNodeResources(from: allocatableMap),
            pods: podItems
        )
    }

    private static func orderedNodeResources(from values: [String: String]) -> [NodeResourceItem] {
        let preferredOrder = ["cpu", "memory", "ephemeral-storage", "hugepages-1Gi", "hugepages-2Mi", "pods"]
        var ordered: [NodeResourceItem] = []
        var consumed = Set<String>()

        for key in preferredOrder {
            if let value = values[key] {
                ordered.append(NodeResourceItem(id: key, name: key, value: value))
                consumed.insert(key)
            }
        }

        let remainingKeys = values.keys
            .filter { !consumed.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        for key in remainingKeys {
            ordered.append(NodeResourceItem(id: key, name: key, value: values[key] ?? "-"))
        }

        return ordered
    }

    private static func formatCPU(_ cores: Double) -> String {
        guard cores > 0 else { return "-" }
        if cores < 1 {
            return "\(Int((cores * 1000).rounded()))m"
        }
        if abs(cores.rounded() - cores) < 0.001 {
            return String(format: "%.0f", cores)
        }
        return String(format: "%.2f", cores)
    }

    private static func formatMemoryGiB(_ gib: Double) -> String {
        guard gib > 0 else { return "-" }
        if gib < 1 {
            let mib = gib * 1024
            if mib >= 10 {
                return String(format: "%.0fMi", mib)
            }
            return String(format: "%.1fMi", mib)
        }
        if gib >= 10 {
            return String(format: "%.1fGi", gib)
        }
        return String(format: "%.2fGi", gib)
    }

    // MARK: - YAML Cleanup

    private static func makeCleanYAML(from rawYAML: String) -> String {
        guard !rawYAML.isEmpty else { return rawYAML }
        guard !rawYAML.hasPrefix("# Error loading YAML:") else { return rawYAML }

        do {
            guard let node = try Yams.compose(yaml: rawYAML) else { return rawYAML }
            let jsonObject = yamlNodeToJSONObject(node)
            let cleaned = pruneKubernetesNoise(in: jsonObject)
            let sanitized = sanitizeForYams(cleaned)
            return try Yams.dump(object: sanitized, allowUnicode: true, sortKeys: true)
        } catch {
            return rawYAML
        }
    }

    private static func pruneKubernetesNoise(in value: Any) -> Any {
        switch value {
        case var dict as [String: Any]:
            for (key, nestedValue) in dict {
                dict[key] = pruneKubernetesNoise(in: nestedValue)
            }

            if var metadata = dict["metadata"] as? [String: Any] {
                metadata.removeValue(forKey: "managedFields")

                if var annotations = metadata["annotations"] as? [String: Any] {
                    annotations.removeValue(forKey: lastAppliedConfigurationAnnotationKey)
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
            return array.map { pruneKubernetesNoise(in: $0) }
        default:
            return value
        }
    }

    private static func sanitizeForYams(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitizeForYams($0) }
        case let array as [Any]:
            return array.map { sanitizeForYams($0) }
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            let doubleValue = number.doubleValue
            let intValue = number.intValue
            if doubleValue == Double(intValue), !number.stringValue.contains(".") {
                return intValue
            }
            return doubleValue
        case let string as NSString:
            return string as String
        case is NSNull:
            return NSNull()
        default:
            return "\(value)"
        }
    }

    private static func yamlNodeToJSONObject(_ node: Yams.Node) -> Any {
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
            return alias.anchor.rawValue
        }
    }
}
