import Foundation
import SwiftkubeClient
import SwiftkubeModel
import Yams

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
