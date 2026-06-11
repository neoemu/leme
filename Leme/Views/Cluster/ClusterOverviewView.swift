import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ClusterOverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var nodeCount: Int?
    @State private var podCount: Int?
    @State private var deploymentCount: Int?
    @State private var serviceCount: Int?
    @State private var namespaceCount: Int?
    @State private var recentEvents: [ResourceItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()

            if isLoading && nodeCount == nil {
                ProgressView("Loading cluster overview...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: errorMessage
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Dimensions.padding) {
                        clusterInfoSection
                        statsGrid
                        recentEventsSection
                    }
                    .padding(Theme.Dimensions.padding)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Cluster Overview")
                .font(Theme.Fonts.title)

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Cluster Info

    private var clusterInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            Text("Cluster Information")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(Theme.Colors.secondaryText)

            if let cluster = appState.activeCluster {
                HStack(spacing: Theme.Dimensions.padding * 2) {
                    infoItem(label: "Name", value: cluster.clusterName)
                    infoItem(label: "Server", value: cluster.clusterURL)
                    if let version = cluster.serverVersion {
                        infoItem(label: "Version", value: "v\(version)")
                    }
                    infoItem(label: "Context", value: cluster.contextName)
                }
                .padding(Theme.Dimensions.padding)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .fill(Color.secondary.opacity(0.05))
                )
            }
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(value)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            Text("Resource Summary")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(Theme.Colors.secondaryText)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: Theme.Dimensions.spacing) {
                statCard(title: "Nodes", count: nodeCount, icon: "desktopcomputer", color: .blue)
                statCard(title: "Pods", count: podCount, icon: "shippingbox", color: .green)
                statCard(title: "Deployments", count: deploymentCount, icon: "arrow.triangle.2.circlepath", color: .orange)
                statCard(title: "Services", count: serviceCount, icon: "network", color: .purple)
                statCard(title: "Namespaces", count: namespaceCount, icon: "folder", color: .cyan)
            }
        }
    }

    private func statCard(title: String, count: Int?, icon: String, color: Color) -> some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)

            if let count {
                Text("\(count)")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Dimensions.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Recent Events

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            Text("Recent Events")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(Theme.Colors.secondaryText)

            if recentEvents.isEmpty {
                Text("No recent events")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(Theme.Dimensions.padding)
            } else {
                Table(recentEvents) {
                    TableColumn("Type") { event in
                        StatusBadge(status: event.status)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Reason") { event in
                        Text(event.extraColumns["reason"] ?? "")
                            .font(Theme.Fonts.tableCell)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Object") { event in
                        Text(event.extraColumns["object"] ?? "")
                            .font(Theme.Fonts.monoSmall)
                    }
                    .width(min: 100, ideal: 160)

                    TableColumn("Message") { event in
                        Text(event.extraColumns["message"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .lineLimit(1)
                    }
                    .width(min: 150, ideal: 300)

                    TableColumn("Age") { event in
                        if let age = event.age {
                            AgeLabel(date: age)
                        } else {
                            Text("-")
                                .font(Theme.Fonts.monoSmall)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                    .width(min: 40, ideal: 60)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 200, maxHeight: 400)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        isLoading = true
        errorMessage = nil

        let service = KubernetesService(client: client)

        // Load all counts concurrently
        async let nodes = loadNodeCount(service: service)
        async let pods = loadPodCount(service: service)
        async let deployments = loadDeploymentCount(service: service)
        async let services = loadServiceCount(service: service)
        async let namespaces = loadNamespaceCount(service: service)
        async let events = loadRecentEvents(service: service)

        nodeCount = await nodes
        podCount = await pods
        deploymentCount = await deployments
        serviceCount = await services
        namespaceCount = await namespaces
        recentEvents = await events

        isLoading = false
    }

    private nonisolated func loadNodeCount(service: KubernetesService) async -> Int {
        do {
            let list = try await service.listClusterScoped(core.v1.Node.self)
            return list.items.count
        } catch {
            return 0
        }
    }

    private nonisolated func loadPodCount(service: KubernetesService) async -> Int {
        do {
            let list = try await service.list(core.v1.Pod.self, in: nil)
            return list.items.count
        } catch {
            return 0
        }
    }

    private nonisolated func loadDeploymentCount(service: KubernetesService) async -> Int {
        do {
            let list = try await service.list(apps.v1.Deployment.self, in: nil)
            return list.items.count
        } catch {
            return 0
        }
    }

    private nonisolated func loadServiceCount(service: KubernetesService) async -> Int {
        do {
            let list = try await service.list(core.v1.Service.self, in: nil)
            return list.items.count
        } catch {
            return 0
        }
    }

    private nonisolated func loadNamespaceCount(service: KubernetesService) async -> Int {
        do {
            let list = try await service.listClusterScoped(core.v1.Namespace.self)
            return list.items.count
        } catch {
            return 0
        }
    }

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
                        "object": "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")"
                    ]
                )
            }
        } catch {
            return []
        }
    }
}
