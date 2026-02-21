import Foundation
import SwiftkubeClient
import SwiftkubeModel
import Yams

@Observable
@MainActor
final class ResourceDetailViewModel {
    var resourceYAML: String = ""
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

    // MARK: - Load Pod Detail

    func loadPodDetail(name: String, namespace: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let pod = try await kubernetesService.get(core.v1.Pod.self, name: name, in: namespace)
            extractMetadata(from: pod)
            resourceYAML = try await kubernetesService.getYAML(pod)
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
            resourceYAML = try await kubernetesService.getYAML(deployment)
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
            resourceYAML = try await kubernetesService.getYAML(resource)
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
            resourceYAML = try await kubernetesService.getYAML(resource)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Apply YAML

    func applyYAML(_ yaml: String, namespace: String?) async {
        do {
            try await kubernetesService.applyYAML(yaml, in: namespace)
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
}
