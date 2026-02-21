import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct EndpointListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.endpoint.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.endpoint.pluralName)
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
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "No Endpoints",
                    message: "No endpoints found in the current namespace."
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
                    TableColumn("Endpoints") { item in
                        Text(item.extraColumns["endpoints"] ?? "0")
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
            core.v1.Endpoints.self,
            kind: .endpoint,
            client: client,
            namespace: appState.selectedNamespace
        ) { resource in
            let subsets = resource.subsets ?? []
            let endpointCount = subsets.reduce(0) { $0 + ($1.addresses?.count ?? 0) }

            return ResourceItem(
                id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
                name: resource.name ?? "",
                namespace: resource.metadata?.namespace,
                status: endpointCount > 0 ? "Active" : "None",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .endpoint,
                extraColumns: [
                    "endpoints": "\(endpointCount)",
                ]
            )
        }
    }
}
