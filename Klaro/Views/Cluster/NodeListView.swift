import Foundation
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
    @State private var nodeWatcher: ResourceWatcher?
    @State private var nodeWatchTasks: [Task<Void, Never>] = []
    @State private var nodeLiveReloadTask: Task<Void, Never>?
    @State private var periodicRefreshTask: Task<Void, Never>?
    @State private var isLiveReloading = false

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
            extraActions: { resource in
                let isCordoned = resource.extraColumns["unschedulable"] == "true"
                return [
                    ResourceRowAction(
                        title: isCordoned ? "Uncordon" : "Cordon",
                        icon: isCordoned ? "play.circle" : "pause.circle"
                    ) {
                        Task {
                            guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                            await viewModel.setNodeSchedulable(name: resource.name, unschedulable: !isCordoned, client: client)
                            await loadData(showLoading: false)
                        }
                    },
                    ResourceRowAction(
                        title: "Drain…",
                        icon: "arrow.down.right.circle",
                        isDestructive: true,
                        needsConfirmation: true,
                        confirmationMessage: "Drain cordons \(resource.name) and evicts all pods (ignoring DaemonSets, deleting emptyDir data). Workloads will reschedule on other nodes."
                    ) {
                        Task {
                            guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                            await viewModel.drainNode(
                                name: resource.name,
                                client: client,
                                contextName: appState.activeCluster?.contextName
                            )
                            await loadData(showLoading: false)
                        }
                    },
                ]
            },
            customCellRenderer: { column, resource in
                nodeCellRenderer(column: column, resource: resource)
            }
        )
        .task {
            await loadData()
            await startLiveUpdates()
        }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task {
                await loadData()
                await startLiveUpdates()
            }
        }
        .onDisappear {
            stopLiveUpdates()
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

    private func loadData(showLoading: Bool = true) async {
        let isLiveReloadRequest = !showLoading
        if isLiveReloadRequest {
            guard !isLiveReloading else { return }
            isLiveReloading = true
        }
        defer {
            if isLiveReloadRequest {
                isLiveReloading = false
            }
        }

        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        let service = KubernetesService(client: client)
        let metricsService = MetricsService(client: client)

        // Load nodes
        if showLoading {
            viewModel.isLoading = true
        }
        viewModel.errorMessage = nil

        do {
            let nodeList = try await service.listClusterScoped(core.v1.Node.self)

            // Extract capacity from each node
            var capacities: [String: MetricsService.NodeCapacity] = [:]
            for node in nodeList.items {
                let name = stringValue(node.name)
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
        if showLoading {
            viewModel.isLoading = false
        }

        // Load pod counts and resource requests in parallel
        async let podCounts = metricsService.podCountByNode()
        async let resourceRequests = metricsService.resourceRequestsByNode()

        podCountsByNode = await podCounts
        resourceRequestsByNode = await resourceRequests
    }

    private func startLiveUpdates() async {
        stopLiveUpdates()

        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        let watcher = ResourceWatcher(client: client)
        nodeWatcher = watcher
        await MainActor.run {
            viewModel.liveWatchStatus = .syncing
        }

        let nodeTask = Task {
            let stream = await watcher.watchMappedClusterScoped(
                core.v1.Node.self,
                kind: .node,
                mapper: ResourceWatcher.signalMapper(kind: .node)
            )
            await consumeWatchSignals(stream)
        }
        nodeWatchTasks.append(nodeTask)

        let podTask = Task {
            let stream = await watcher.watchMapped(
                core.v1.Pod.self,
                kind: .pod,
                in: nil,
                mapper: ResourceWatcher.signalMapper(kind: .pod)
            )
            await consumeWatchSignals(stream)
        }
        nodeWatchTasks.append(podTask)

        periodicRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.resourceRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await loadData(showLoading: false)
            }
        }
    }

    private func consumeWatchSignals(_ stream: AsyncStream<MappedWatchEvent>) async {
        for await event in stream {
            guard !Task.isCancelled else { break }
            await MainActor.run {
                if case .error(let reason) = event.change {
                    viewModel.liveWatchStatus = .recovering(lastEventAt: nil, reason: reason)
                    return
                }
                viewModel.liveWatchStatus = .live(lastEventAt: Date())
                scheduleLiveReload()
            }
        }
    }

    private func scheduleLiveReload() {
        nodeLiveReloadTask?.cancel()
        nodeLiveReloadTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadData(showLoading: false)
        }
    }

    private func stopLiveUpdates() {
        nodeWatchTasks.forEach { $0.cancel() }
        nodeWatchTasks.removeAll()

        nodeLiveReloadTask?.cancel()
        nodeLiveReloadTask = nil
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil

        if let nodeWatcher {
            Task {
                await nodeWatcher.stopAll()
            }
        }
        nodeWatcher = nil
        viewModel.liveWatchStatus = .off
    }

    // MARK: - Node Mapper

    private nonisolated func nodeToResourceItem(_ node: core.v1.Node) -> ResourceItem {
        // Determine status from conditions
        let conditions = node.status?.conditions ?? []
        let readyCondition = conditions.first { $0.type == "Ready" }
        let isUnschedulable = node.spec?.unschedulable == true
        var status: String
        if readyCondition?.status == "True" {
            status = "Ready"
        } else {
            status = "NotReady"
        }
        if isUnschedulable {
            status += ",SchedulingDisabled"
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
        let taintsStr = taints.map { taint in
            let key = stringValue(taint.key)
            let value = stringValue(taint.value)
            let effect = stringValue(taint.effect)
            return "\(key)=\(value):\(effect)"
        }.joined(separator: ", ")

        let nodeName = stringValue(node.name)

        var extra: [String: String] = [:]
        extra["roles"] = rolesString
        extra["version"] = version
        extra["internalIP"] = internalIP
        extra["os"] = os
        extra["taints"] = taintsStr
        extra["unschedulable"] = isUnschedulable ? "true" : "false"

        return ResourceItem(
            id: nodeName.isEmpty ? UUID().uuidString : nodeName,
            name: nodeName,
            namespace: nil,
            status: status,
            age: node.metadata?.creationTimestamp,
            labels: labels,
            annotations: node.metadata?.annotations ?? [:],
            kind: .node,
            extraColumns: extra
        )
    }

    private nonisolated func stringValue(_ value: String?) -> String {
        value ?? ""
    }

    private nonisolated func stringValue(_ value: String) -> String {
        value
    }
}
