import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ClusterRoleListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var resourceToDelete: ResourceItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading cluster roles...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Cluster Roles",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: ResourceKind.clusterRole.icon,
                    title: "No Cluster Roles",
                    message: "No cluster roles found."
                )
            } else {
                clusterRoleTable
            }
        }
        .task { await loadData() }
        .confirmationDialog(
            "Delete \(resourceToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let resource = resourceToDelete {
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        await viewModel.deleteResource(kind: .clusterRole, name: resource.name, namespace: resource.namespace, client: client)
                    }
                }
                resourceToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                resourceToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
    }

    private var clusterRoleTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Name") { item in
                Text(item.name)
                    .font(Theme.Fonts.monoSmall)
                    .contextMenu {
                        Button(role: .destructive) {
                            resourceToDelete = item
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .width(min: 150, ideal: 250)

            TableColumn("Rules") { item in
                Text(item.extraColumns["rules"] ?? "0")
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
        await viewModel.loadClusterScopedResources(
            rbac.v1.ClusterRole.self,
            kind: .clusterRole,
            client: client,
            mapper: clusterRoleToResourceItem
        )
    }

    private nonisolated func clusterRoleToResourceItem(_ cr: rbac.v1.ClusterRole) -> ResourceItem {
        let rulesCount = cr.rules?.count ?? 0

        return ResourceItem(
            id: cr.name ?? "",
            name: cr.name ?? "",
            namespace: nil,
            status: "Active",
            age: cr.metadata?.creationTimestamp,
            labels: cr.metadata?.labels ?? [:],
            annotations: cr.metadata?.annotations ?? [:],
            kind: .clusterRole,
            extraColumns: [
                "rules": "\(rulesCount)",
            ]
        )
    }
}
