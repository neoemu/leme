import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ClusterDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ClusterDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
                // Header
                dashboardHeader

                // Info pills row
                infoPillsRow

                // Stats cards
                statsRow

                // Capacity bars
                capacitySection

                // Recent events
                eventsSection
            }
            .padding(Theme.Dimensions.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.contentBackground)
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Cluster Dashboard")
                .font(Theme.Fonts.title)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Refresh dashboard")
        }
    }

    // MARK: - Info Pills

    private var infoPillsRow: some View {
        HStack(spacing: Theme.Dimensions.sectionSpacing) {
            InfoPill(label: "Provider", value: viewModel.provider)
            if !viewModel.kubernetesVersion.isEmpty {
                InfoPill(label: "Kubernetes", value: "v\(viewModel.kubernetesVersion)")
            }
            if !viewModel.architecture.isEmpty {
                InfoPill(label: "Architecture", value: viewModel.architecture)
            }
            if !viewModel.clusterAge.isEmpty {
                InfoPill(label: "Created", value: viewModel.clusterAge)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Dimensions.spacing)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            CountBadge(
                count: viewModel.totalResources,
                errorCount: viewModel.errorResources > 0 ? viewModel.errorResources : nil,
                title: "Resources",
                icon: "square.grid.2x2",
                color: Theme.Colors.accent
            )

            CountBadge(
                count: viewModel.nodeCount,
                errorCount: viewModel.errorNodes > 0 ? viewModel.errorNodes : nil,
                title: "Nodes",
                icon: "desktopcomputer",
                color: Theme.Colors.running
            )

            CountBadge(
                count: viewModel.deploymentCount,
                errorCount: viewModel.errorDeployments > 0 ? viewModel.errorDeployments : nil,
                title: "Deployments",
                icon: "arrow.triangle.2.circlepath",
                color: Theme.Colors.succeeded
            )
        }
    }

    // MARK: - Capacity

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            Text("Cluster Capacity")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(.primary)

            let capacity = viewModel.capacity

            HStack(spacing: Theme.Dimensions.sectionSpacing) {
                VStack(spacing: Theme.Dimensions.spacing) {
                    CapacityBar(
                        label: "Pods",
                        used: Double(capacity.usedPods),
                        total: Double(capacity.totalPods),
                        unit: ""
                    )

                    CapacityBar(
                        label: "CPU Reserved",
                        used: capacity.reservedCPUCores,
                        total: capacity.totalCPUCores,
                        unit: "cores"
                    )

                    CapacityBar(
                        label: "Memory Reserved",
                        used: capacity.reservedMemoryGiB,
                        total: capacity.totalMemoryGiB,
                        unit: "GiB"
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Dimensions.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            HStack {
                Text("Recent Events")
                    .font(Theme.Fonts.subtitle)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.recentEvents.count) events")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            if viewModel.recentEvents.isEmpty {
                Text("No recent events.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .padding(.vertical, Theme.Dimensions.spacing)
            } else {
                eventsTable
            }
        }
        .padding(Theme.Dimensions.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var eventsTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("TYPE")
                    .frame(width: 70, alignment: .leading)
                Text("REASON")
                    .frame(width: 120, alignment: .leading)
                Text("OBJECT")
                    .frame(width: 200, alignment: .leading)
                Text("MESSAGE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("COUNT")
                    .frame(width: 50, alignment: .trailing)
                Text("AGE")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(Theme.Fonts.tableHeader)
            .foregroundStyle(Theme.Colors.secondaryText)
            .padding(.vertical, Theme.Dimensions.smallSpacing)
            .padding(.horizontal, Theme.Dimensions.spacing)

            Divider()

            // Rows
            ForEach(viewModel.recentEvents) { event in
                HStack(spacing: 0) {
                    StatusBadge(status: event.status)
                        .frame(width: 70, alignment: .leading)

                    Text(event.extraColumns["reason"] ?? "")
                        .font(Theme.Fonts.tableCell)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)

                    Text(event.extraColumns["object"] ?? "")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)

                    Text(event.extraColumns["message"] ?? "")
                        .font(Theme.Fonts.tableCell)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(event.extraColumns["count"] ?? "")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(width: 50, alignment: .trailing)

                    if let age = event.age {
                        AgeLabel(date: age)
                            .frame(width: 60, alignment: .trailing)
                    } else {
                        Text("-")
                            .font(Theme.Fonts.monoSmall)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, Theme.Dimensions.spacing)

                Divider()
                    .padding(.leading, Theme.Dimensions.spacing)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let cluster = appState.activeCluster,
              let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }
        await viewModel.loadDashboard(client: client, cluster: cluster)
    }
}
