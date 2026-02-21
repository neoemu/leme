import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ServiceAccountListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.serviceAccount.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.serviceAccount.pluralName)
                    .font(Theme.Fonts.title)
                Spacer()
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "person.circle",
                    title: "No Service Accounts",
                    message: "No service accounts found in the current namespace."
                )
            } else {
                Table(viewModel.filteredResources, selection: Binding(
                    get: { appState.selectedResourceID },
                    set: { appState.selectResource($0) }
                )) {
                    TableColumn("Name") { item in
                        Text(item.name)
                            .font(Theme.Fonts.tableCell)
                    }
                    TableColumn("Namespace") { item in
                        Text(item.namespace ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Secrets") { item in
                        Text(item.extraColumns["secrets"] ?? "0")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Age") { item in
                        if let date = item.age {
                            AgeLabel(date: date)
                        } else {
                            Text("-")
                                .font(Theme.Fonts.tableCell)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
                .font(Theme.Fonts.tableCell)
            }
        }
        .task { await loadData() }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            core.v1.ServiceAccount.self,
            kind: .serviceAccount,
            client: client,
            namespace: appState.selectedNamespace
        ) { resource in
            let secretsCount = resource.secrets?.count ?? 0

            return ResourceItem(
                id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
                name: resource.name ?? "",
                namespace: resource.metadata?.namespace,
                status: "Active",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .serviceAccount,
                extraColumns: [
                    "secrets": "\(secretsCount)",
                ]
            )
        }
    }
}
