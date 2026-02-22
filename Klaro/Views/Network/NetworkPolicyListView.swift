import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct NetworkPolicyListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var resourceToDelete: ResourceItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading network policies...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Network Policies",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: ResourceKind.networkPolicy.icon,
                    title: "No Network Policies",
                    message: "No network policies found in the selected namespace."
                )
            } else {
                networkPolicyTable
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
                        await viewModel.deleteResource(kind: .networkPolicy, name: resource.name, namespace: resource.namespace, client: client)
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

    private var networkPolicyTable: some View {
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

            TableColumn("Pod Selector") { item in
                Text(item.extraColumns["podSelector"] ?? "<all>")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Policy Types") { item in
                Text(item.extraColumns["policyTypes"] ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 80, ideal: 120)

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
            networking.v1.NetworkPolicy.self,
            kind: .networkPolicy,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: networkPolicyToResourceItem
        )
    }

    private nonisolated func networkPolicyToResourceItem(_ np: networking.v1.NetworkPolicy) -> ResourceItem {
        let matchLabels = np.spec?.podSelector.matchLabels ?? [:]
        let podSelector = matchLabels.isEmpty
            ? "<all>"
            : matchLabels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")

        let policyTypes = np.spec?.policyTypes?.joined(separator: ", ") ?? "-"

        return ResourceItem(
            id: "\(np.metadata?.namespace ?? "")/\(np.name ?? "")",
            name: np.name ?? "",
            namespace: np.metadata?.namespace,
            status: "Active",
            age: np.metadata?.creationTimestamp,
            labels: np.metadata?.labels ?? [:],
            annotations: np.metadata?.annotations ?? [:],
            kind: .networkPolicy,
            extraColumns: [
                "podSelector": podSelector,
                "policyTypes": policyTypes,
            ]
        )
    }
}
