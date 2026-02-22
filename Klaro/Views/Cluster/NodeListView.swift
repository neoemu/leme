import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct NodeListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()
    @State private var nodeCapacities: [String: MetricsService.NodeCapacity] = [:]
    @State private var podCountsByNode: [String: Int] = [:]
    @State private var resourceRequestsByNode: [String: MetricsService.NodeResourceUsage] = [:]

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "State", key: "status", width: 80, sortField: .status),
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Roles", key: "roles", width: 100),
        ResourceTableColumn(title: "Version", key: "version", width: 130),
        ResourceTableColumn(title: "Int. IP", key: "internalIP", width: 120),
        ResourceTableColumn(title: "OS", key: "os", width: 60),
        ResourceTableColumn(title: "CPU", key: "cpuBar", width: 100),
        ResourceTableColumn(title: "RAM", key: "ramBar", width: 100),
        ResourceTableColumn(title: "Pods", key: "podsBar", width: 100),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    do {
                        let yaml = try await viewModel.fetchResourceYAML(
                            kind: .node,
                            name: resource.name,
                            namespace: resource.namespace,
                            client: client
                        )
                        appState.showYAMLEditor(resourceID: resource.id, title: "YAML - \(resource.name)", yaml: yaml)
                    } catch {
                        appState.showYAMLEditor(
                            resourceID: resource.id,
                            title: "YAML - \(resource.name)",
                            yaml: "# Error loading YAML: \(error.localizedDescription)"
                        )
                    }
                }
            },
            onDelete: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.deleteResource(kind: .node, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: .node, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            customCellRenderer: { column, resource in
                nodeCellRenderer(column: column, resource: resource)
            }
        )
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Custom Cell Renderer

    private func nodeCellRenderer(column: ResourceTableColumn, resource: ResourceItem) -> AnyView? {
        switch column.key {
        case "cpuBar":
            return cpuBarView(for: resource)
        case "ramBar":
            return ramBarView(for: resource)
        case "podsBar":
            return podsBarView(for: resource)
        default:
            return nil
        }
    }

    private func cpuBarView(for resource: ResourceItem) -> AnyView {
        let nodeName = resource.name
        let capacity = nodeCapacities[nodeName]
        let requests = resourceRequestsByNode[nodeName]

        if let cap = capacity, cap.cpuCores > 0 {
            let used = requests?.cpuRequested ?? 0
            return AnyView(
                CapacityBar(
                    label: "CPU",
                    used: used,
                    total: cap.cpuCores,
                    unit: "cores",
                    compact: true
                )
            )
        }
        return AnyView(
            Text("-")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        )
    }

    private func ramBarView(for resource: ResourceItem) -> AnyView {
        let nodeName = resource.name
        let capacity = nodeCapacities[nodeName]
        let requests = resourceRequestsByNode[nodeName]

        if let cap = capacity, cap.memoryGiB > 0 {
            let used = requests?.memoryRequestedGiB ?? 0
            return AnyView(
                CapacityBar(
                    label: "RAM",
                    used: used,
                    total: cap.memoryGiB,
                    unit: "GiB",
                    compact: true
                )
            )
        }
        return AnyView(
            Text("-")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        )
    }

    private func podsBarView(for resource: ResourceItem) -> AnyView {
        let nodeName = resource.name
        let capacity = nodeCapacities[nodeName]
        let podCount = podCountsByNode[nodeName] ?? 0

        if let cap = capacity, cap.maxPods > 0 {
            return AnyView(
                CapacityBar(
                    label: "Pods",
                    used: Double(podCount),
                    total: Double(cap.maxPods),
                    unit: "",
                    compact: true
                )
            )
        }
        return AnyView(
            Text("-")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        )
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        let service = KubernetesService(client: client)
        let metricsService = MetricsService(client: client)

        // Load nodes
        viewModel.isLoading = true
        viewModel.errorMessage = nil

        do {
            let nodeList = try await service.listClusterScoped(core.v1.Node.self)

            // Extract capacity from each node
            var capacities: [String: MetricsService.NodeCapacity] = [:]
            for node in nodeList.items {
                let name = node.name ?? ""
                capacities[name] = MetricsService.extractNodeCapacity(from: node)
            }
            nodeCapacities = capacities

            // Map nodes to ResourceItem with enriched data
            viewModel.resources = nodeList.items.map { node in
                nodeToResourceItem(node)
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
        viewModel.isLoading = false

        // Load pod counts and resource requests in parallel
        async let podCounts = metricsService.podCountByNode()
        async let resourceRequests = metricsService.resourceRequestsByNode()

        podCountsByNode = await podCounts
        resourceRequestsByNode = await resourceRequests
    }

    // MARK: - Node Mapper

    private nonisolated func nodeToResourceItem(_ node: core.v1.Node) -> ResourceItem {
        // Determine status from conditions
        let conditions = node.status?.conditions ?? []
        let readyCondition = conditions.first { $0.type == "Ready" }
        let status: String
        if readyCondition?.status == "True" {
            status = "Ready"
        } else {
            status = "NotReady"
        }

        // Extract roles from labels
        let labels = node.metadata?.labels ?? [:]
        var roles: [String] = []
        for (key, _) in labels {
            if key.hasPrefix("node-role.kubernetes.io/") {
                let role = String(key.dropFirst("node-role.kubernetes.io/".count))
                if !role.isEmpty {
                    roles.append(role)
                }
            }
        }
        let rolesString = roles.isEmpty ? "<none>" : roles.sorted().joined(separator: ", ")

        // Extract node info
        let nodeInfo = node.status?.nodeInfo
        let version = nodeInfo?.kubeletVersion ?? ""
        let os = nodeInfo?.operatingSystem ?? ""

        // Extract Internal IP
        let addresses = node.status?.addresses ?? []
        let internalIP = addresses.first { $0.type == "InternalIP" }?.address ?? ""

        // Extract taints for tooltip
        let taints = node.spec?.taints ?? []
        let taintsStr = taints.map { "\($0.key ?? "")=\($0.value ?? ""):\($0.effect ?? "")" }.joined(separator: ", ")

        var extra: [String: String] = [:]
        extra["roles"] = rolesString
        extra["version"] = version
        extra["internalIP"] = internalIP
        extra["os"] = os
        extra["taints"] = taintsStr

        return ResourceItem(
            id: node.name ?? UUID().uuidString,
            name: node.name ?? "",
            namespace: nil,
            status: status,
            age: node.metadata?.creationTimestamp,
            labels: labels,
            annotations: node.metadata?.annotations ?? [:],
            kind: .node,
            extraColumns: extra
        )
    }
}
