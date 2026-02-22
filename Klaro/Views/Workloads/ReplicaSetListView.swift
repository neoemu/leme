import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ReplicaSetListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading replica sets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Replica Sets",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: ResourceKind.replicaSet.icon,
                    title: "No Replica Sets",
                    message: "No replica sets found in the selected namespace."
                )
            } else {
                replicaSetTable
            }
        }
        .task { await loadData() }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private var replicaSetTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Name") { item in
                Text(item.name)
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Namespace") { item in
                Text(item.namespace ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Desired") { item in
                Text(item.extraColumns["desired"] ?? "0")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Current") { item in
                Text(item.extraColumns["current"] ?? "0")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Ready") { item in
                Text(item.extraColumns["ready"] ?? "0")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Age") { item in
                if let age = item.age {
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

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            apps.v1.ReplicaSet.self,
            kind: .replicaSet,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: replicaSetToResourceItem
        )
    }

    private nonisolated func replicaSetToResourceItem(_ rs: apps.v1.ReplicaSet) -> ResourceItem {
        let desired = rs.spec?.replicas ?? 0
        let current = rs.status?.replicas ?? 0
        let ready = rs.status?.readyReplicas ?? 0

        let status: String
        if ready == desired && desired > 0 {
            status = "Running"
        } else if desired == 0 {
            status = "Scaled Down"
        } else {
            status = "Updating"
        }

        return ResourceItem(
            id: "\(rs.metadata?.namespace ?? "")/\(rs.name ?? "")",
            name: rs.name ?? "",
            namespace: rs.metadata?.namespace,
            status: status,
            age: rs.metadata?.creationTimestamp,
            labels: rs.metadata?.labels ?? [:],
            annotations: rs.metadata?.annotations ?? [:],
            kind: .replicaSet,
            extraColumns: [
                "desired": "\(desired)",
                "current": "\(current)",
                "ready": "\(ready)",
            ]
        )
    }
}
