import Foundation
import SwiftkubeClient
import SwiftkubeModel

@Observable
@MainActor
final class ClusterDashboardViewModel {
    var isLoading = false
    var errorMessage: String?

    // Provider info
    var provider: String = "Unknown"
    var kubernetesVersion: String = ""
    var architecture: String = ""
    var clusterAge: String = ""

    // Stats
    var totalResources: Int = 0
    var errorResources: Int = 0
    var nodeCount: Int = 0
    var errorNodes: Int = 0
    var deploymentCount: Int = 0
    var errorDeployments: Int = 0

    // Capacity
    var capacity = ClusterCapacity()

    // Events
    var recentEvents: [ResourceItem] = []

    func loadDashboard(client: KubernetesClient, cluster: ClusterConnection) async {
        isLoading = true
        errorMessage = nil

        let service = KubernetesService(client: client)
        let metricsService = MetricsService(client: client)

        // Load all data concurrently
        async let nodesResult: core.v1.NodeList? = {
            try? await service.listClusterScoped(core.v1.Node.self)
        }()

        async let podsResult: core.v1.PodList? = {
            try? await service.list(core.v1.Pod.self, in: nil)
        }()

        async let deploymentsResult: apps.v1.DeploymentList? = {
            try? await service.list(apps.v1.Deployment.self, in: nil)
        }()

        async let servicesResult: core.v1.ServiceList? = {
            try? await service.list(core.v1.Service.self, in: nil)
        }()

        async let eventsResult: [ResourceItem] = loadRecentEvents(service: service)

        async let capacityResult: ClusterCapacity = metricsService.computeClusterCapacity()

        let nodes = await nodesResult
        let pods = await podsResult
        let deployments = await deploymentsResult
        let services = await servicesResult
        recentEvents = await eventsResult
        capacity = await capacityResult

        // Provider detection
        provider = detectProvider(cluster: cluster, nodes: nodes?.items ?? [])

        // Version
        kubernetesVersion = cluster.serverVersion ?? ""

        // Architecture
        let nodeInfoArch = nodes?.items.first?.status?.nodeInfo?.architecture ?? ""
        architecture = nodeInfoArch.isEmpty ? "Unknown" : nodeInfoArch.capitalized

        // Cluster age (oldest node creation)
        if let oldest = nodes?.items.compactMap({ $0.metadata?.creationTimestamp }).min() {
            clusterAge = oldest.relativeAge
        }

        // Node stats
        let allNodes = nodes?.items ?? []
        nodeCount = allNodes.count
        errorNodes = allNodes.filter { node in
            let readyCondition = node.status?.conditions?.first { $0.type == "Ready" }
            return readyCondition?.status != "True"
        }.count

        // Pod stats
        let allPods = pods?.items ?? []
        let errorPods = allPods.filter { pod in
            let phase = pod.status?.phase ?? ""
            return !["Running", "Succeeded"].contains(phase)
        }.count

        // Deployment stats
        let allDeploys = deployments?.items ?? []
        deploymentCount = allDeploys.count
        errorDeployments = allDeploys.filter { deploy in
            let ready = deploy.status?.readyReplicas ?? 0
            let desired = deploy.spec?.replicas ?? 0
            return ready < desired
        }.count

        // Total resource count
        let serviceCount = services?.items.count ?? 0
        totalResources = allNodes.count + allPods.count + allDeploys.count + serviceCount
        errorResources = errorPods + errorDeployments + errorNodes

        isLoading = false
    }

    // MARK: - Provider Detection

    private nonisolated func detectProvider(cluster: ClusterConnection, nodes: [core.v1.Node]) -> String {
        let url = cluster.clusterURL.lowercased()

        // URL-based detection
        if url.contains(".azmk8s.io") || url.contains("azure") { return "Azure AKS" }
        if url.contains(".eks.amazonaws.com") { return "Amazon EKS" }
        if url.contains(".gke.") || url.contains("container.googleapis.com") { return "Google GKE" }

        // Label-based detection
        let labels = nodes.first?.metadata?.labels ?? [:]
        if labels.keys.contains(where: { $0.contains("cloud.google.com") || $0.contains("gke") }) { return "Google GKE" }
        if labels.keys.contains(where: { $0.contains("eks.amazonaws.com") }) { return "Amazon EKS" }
        if labels.keys.contains(where: { $0.contains("kubernetes.azure.com") }) { return "Azure AKS" }
        if labels.keys.contains(where: { $0.contains("minikube") }) { return "Minikube" }
        if labels.keys.contains(where: { $0.contains("k3s") }) { return "K3s" }
        if labels.keys.contains(where: { $0.contains("microk8s") }) { return "MicroK8s" }

        // Version-based detection
        let version = nodes.first?.status?.nodeInfo?.kubeletVersion ?? ""
        if version.contains("gke") { return "Google GKE" }
        if version.contains("eks") { return "Amazon EKS" }
        if version.contains("k3s") { return "K3s" }

        return "Kubernetes"
    }

    // MARK: - Events

    private nonisolated func loadRecentEvents(service: KubernetesService) async -> [ResourceItem] {
        do {
            let list = try await service.list(core.v1.Event.self, in: nil)
            let sorted = list.items
                .sorted { a, b in
                    (a.metadata?.creationTimestamp ?? .distantPast) > (b.metadata?.creationTimestamp ?? .distantPast)
                }
                .prefix(20)

            return sorted.map { event in
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
                        "object": "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")",
                    ]
                )
            }
        } catch {
            return []
        }
    }
}
