import Foundation
import SwiftkubeClient
import SwiftkubeModel

// MARK: - Metrics Data Models

struct NodeMetrics: Sendable {
    let name: String
    let cpuUsage: Double        // in cores
    let memoryUsage: Double     // in bytes
}

struct PodMetricsItem: Sendable {
    let name: String
    let namespace: String
    let containers: [ContainerMetricsItem]
}

struct ContainerMetricsItem: Sendable {
    let name: String
    let cpuUsage: Double        // in cores
    let memoryUsage: Double     // in bytes
}

// MARK: - Cluster Capacity (aggregated from nodes)

struct ClusterCapacity: Sendable {
    var totalPods: Int = 0
    var usedPods: Int = 0
    var totalCPUCores: Double = 0
    var reservedCPUCores: Double = 0
    var usedCPUCores: Double = 0
    var totalMemoryGiB: Double = 0
    var reservedMemoryGiB: Double = 0
    var usedMemoryGiB: Double = 0
    var metricsAvailable: Bool = false
}

// MARK: - MetricsService

/// Fetches cluster capacity information from node allocatable resources
/// and (optionally) from the Kubernetes Metrics API (metrics.k8s.io/v1beta1).
actor MetricsService {

    private let client: KubernetesClient

    init(client: KubernetesClient) {
        self.client = client
    }

    // MARK: - Cluster Capacity (always available, from node spec)

    /// Computes cluster capacity from node allocatable + pod resource requests.
    /// This does NOT require metrics-server — it uses core K8s API data.
    func computeClusterCapacity() async -> ClusterCapacity {
        var capacity = ClusterCapacity()

        let service = KubernetesService(client: client)

        // Load nodes + pods concurrently
        async let nodesResult: core.v1.NodeList? = {
            try? await service.listClusterScoped(core.v1.Node.self)
        }()

        async let podsResult: core.v1.PodList? = {
            try? await service.list(core.v1.Pod.self, in: nil)
        }()

        let nodes = await nodesResult
        let pods = await podsResult

        // Aggregate node allocatable capacity
        for node in nodes?.items ?? [] {
            let allocatable = node.status?.allocatable ?? [:]

            // CPU allocatable
            if let cpuStr = allocatable["cpu"]?.description {
                capacity.totalCPUCores += cpuStr.parseKubernetesCPU()
            }

            // Memory allocatable
            if let memStr = allocatable["memory"]?.description {
                capacity.totalMemoryGiB += memStr.parseKubernetesMemoryGiB()
            }

            // Pods allocatable
            if let podsStr = allocatable["pods"]?.description {
                capacity.totalPods += Int(podsStr) ?? 0
            }
        }

        // Count used pods
        let allPods = pods?.items ?? []
        capacity.usedPods = allPods.count

        // Sum reserved CPU/memory from pod resource requests
        for pod in allPods {
            for container in pod.spec?.containers ?? [] {
                if let cpuReq = container.resources?.requests?["cpu"]?.description {
                    capacity.reservedCPUCores += cpuReq.parseKubernetesCPU()
                }
                if let memReq = container.resources?.requests?["memory"]?.description {
                    capacity.reservedMemoryGiB += memReq.parseKubernetesMemoryGiB()
                }
            }
        }

        return capacity
    }

    // MARK: - Per-Node Capacity (from node status)

    /// Returns allocatable CPU, memory, and pods for a single node.
    struct NodeCapacity: Sendable {
        let cpuCores: Double
        let memoryGiB: Double
        let maxPods: Int
    }

    static func extractNodeCapacity(from node: core.v1.Node) -> NodeCapacity {
        let allocatable = node.status?.allocatable ?? [:]

        let cpu = (allocatable["cpu"]?.description ?? "0").parseKubernetesCPU()
        let mem = (allocatable["memory"]?.description ?? "0").parseKubernetesMemoryGiB()
        let pods = Int(allocatable["pods"]?.description ?? "0") ?? 0

        return NodeCapacity(cpuCores: cpu, memoryGiB: mem, maxPods: pods)
    }

    // MARK: - Pod Count Per Node

    /// Counts how many pods are running on each node.
    func podCountByNode() async -> [String: Int] {
        let service = KubernetesService(client: client)
        guard let pods = try? await service.list(core.v1.Pod.self, in: nil) else {
            return [:]
        }

        var counts: [String: Int] = [:]
        for pod in pods.items {
            if let nodeName = pod.spec?.nodeName {
                counts[nodeName, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Resource Request Aggregation Per Node

    /// Sums CPU and memory requests for pods on each node.
    struct NodeResourceUsage: Sendable {
        let cpuRequested: Double       // in cores
        let memoryRequestedGiB: Double // in GiB
    }

    func resourceRequestsByNode() async -> [String: NodeResourceUsage] {
        let service = KubernetesService(client: client)
        guard let pods = try? await service.list(core.v1.Pod.self, in: nil) else {
            return [:]
        }

        var result: [String: (cpu: Double, mem: Double)] = [:]
        for pod in pods.items {
            guard let nodeName = pod.spec?.nodeName else { continue }
            var entry = result[nodeName, default: (cpu: 0, mem: 0)]
            for container in pod.spec?.containers ?? [] {
                if let cpuReq = container.resources?.requests?["cpu"]?.description {
                    entry.cpu += cpuReq.parseKubernetesCPU()
                }
                if let memReq = container.resources?.requests?["memory"]?.description {
                    entry.mem += memReq.parseKubernetesMemoryGiB()
                }
            }
            result[nodeName] = entry
        }

        return result.mapValues { NodeResourceUsage(cpuRequested: $0.cpu, memoryRequestedGiB: $0.mem) }
    }
}
