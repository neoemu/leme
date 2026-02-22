import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct RoleBindingListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var resourceToDelete: ResourceItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading role bindings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Role Bindings",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: ResourceKind.roleBinding.icon,
                    title: "No Role Bindings",
                    message: "No role bindings found in the selected namespace."
                )
            } else {
                roleBindingTable
            }
        }
        .task { await loadData() }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
        .confirmationDialog(
            "Delete \(resourceToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let resource = resourceToDelete {
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        await viewModel.deleteResource(kind: .roleBinding, name: resource.name, namespace: resource.namespace, client: client)
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

    private var roleBindingTable: some View {
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
            .width(min: 120, ideal: 200)

            TableColumn("Namespace") { item in
                Text(item.namespace ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Role Ref") { item in
                Text(item.extraColumns["roleRef"] ?? "-")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Subjects") { item in
                Text(item.extraColumns["subjects"] ?? "0")
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
            rbac.v1.RoleBinding.self,
            kind: .roleBinding,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: roleBindingToResourceItem
        )
    }

    private nonisolated func roleBindingToResourceItem(_ rb: rbac.v1.RoleBinding) -> ResourceItem {
        let roleRef = "\(rb.roleRef.kind)/\(rb.roleRef.name)"
        let subjectsCount = rb.subjects?.count ?? 0

        return ResourceItem(
            id: "\(rb.metadata?.namespace ?? "")/\(rb.name ?? "")",
            name: rb.name ?? "",
            namespace: rb.metadata?.namespace,
            status: "Active",
            age: rb.metadata?.creationTimestamp,
            labels: rb.metadata?.labels ?? [:],
            annotations: rb.metadata?.annotations ?? [:],
            kind: .roleBinding,
            extraColumns: [
                "roleRef": roleRef,
                "subjects": "\(subjectsCount)",
            ]
        )
    }
}
