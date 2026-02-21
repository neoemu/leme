import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct NodeListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading nodes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Nodes",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "desktopcomputer",
                    title: "No Nodes",
                    message: "No nodes found in this cluster."
                )
            } else {
                nodeTable
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: ResourceKind.node.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Nodes")
                .font(Theme.Fonts.title)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(viewModel.filteredResources.count) nodes")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Table

    private var nodeTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Name") { node in
                Text(node.name)
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Status") { node in
                StatusBadge(status: node.status)
            }
            .width(min: 60, ideal: 100)

            TableColumn("Roles") { node in
                Text(node.extraColumns["roles"] ?? "<none>")
                    .font(Theme.Fonts.tableCell)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Age") { node in
                if let age = node.age {
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
        .onChange(of: viewModel.selectedResourceID) { _, newValue in
            appState.selectResource(newValue)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        await viewModel.loadClusterScopedResources(
            core.v1.Node.self,
            kind: .node,
            client: client,
            mapper: nodeToResourceItem
        )
    }

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

        var extra: [String: String] = [:]
        extra["roles"] = rolesString

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
